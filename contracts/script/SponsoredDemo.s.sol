// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import {GembaForwarder} from "../src/paymaster/GembaForwarder.sol";
import {WorkplaceCheckIn} from "../src/paymaster/WorkplaceCheckIn.sol";

/// @notice Live devnet demo of sponsored gas (Phase 4). The RELAYER (the
/// institution's sponsoring wallet, holding GMB) deploys the forwarder + target
/// and submits the EMPLOYEE's signed check-in, paying the gas. The employee holds
/// 0 GMB and only signed off-chain. Run:
///
///   forge script script/SponsoredDemo.s.sol --rpc-url http://localhost:8545 \
///     --broadcast --private-key <RELAYER_PK> -vv
///
/// Env: RELAYER_PK (sponsoring wallet), EMPLOYEE_PK (a fresh, unfunded key).
contract SponsoredDemo is Script {
    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant REQUEST_TYPEHASH =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)");

    function run() external {
        uint256 relayerPk = vm.envUint("RELAYER_PK");
        uint256 employeePk = vm.envUint("EMPLOYEE_PK");
        address relayer = vm.addr(relayerPk);
        address employee = vm.addr(employeePk);

        console.log("relayer (sponsor):", relayer, "balance:", relayer.balance);
        console.log("employee:        ", employee, "balance:", employee.balance);

        // 1. Relayer deploys the forwarder and the target.
        vm.startBroadcast(relayerPk);
        GembaForwarder forwarder = new GembaForwarder();
        WorkplaceCheckIn target = new WorkplaceCheckIn(address(forwarder));
        vm.stopBroadcast();

        // 2. Employee signs a check-in request off-chain (no gas, no GMB).
        ERC2771Forwarder.ForwardRequestData memory req = _buildRequest(employeePk, address(forwarder), address(target));

        // 3. Relayer submits the employee's signed request, paying the gas.
        vm.startBroadcast(relayerPk);
        forwarder.execute(req);
        vm.stopBroadcast();

        console.log("forwarder:", address(forwarder));
        console.log("target:   ", address(target));
        console.log("employee check-ins (expect 1):", target.checkIns(employee));
        console.log("attributed to employee?:", target.lastCheckedIn() == employee);
    }

    function _buildRequest(uint256 employeePk, address forwarder, address target)
        internal
        view
        returns (ERC2771Forwarder.ForwardRequestData memory req)
    {
        address employee = vm.addr(employeePk);
        bytes memory data = abi.encodeCall(WorkplaceCheckIn.checkIn, ());
        uint48 deadline = uint48(block.timestamp + 1 hours);
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes("GembaForwarder")), keccak256(bytes("1")), block.chainid, forwarder)
        );
        bytes32 structHash = keccak256(
            abi.encode(REQUEST_TYPEHASH, employee, target, uint256(0), uint256(200000), ERC2771Forwarder(payable(forwarder)).nonces(employee), deadline, keccak256(data))
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(employeePk, keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash)));
        req = ERC2771Forwarder.ForwardRequestData({
            from: employee,
            to: target,
            value: 0,
            gas: 200000,
            deadline: deadline,
            data: data,
            signature: abi.encodePacked(r, s, v)
        });
    }
}
