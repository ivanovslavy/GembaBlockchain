// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC2771Forwarder} from "@openzeppelin/contracts/metatx/ERC2771Forwarder.sol";
import {GembaForwarder} from "../src/paymaster/GembaForwarder.sol";
import {WorkplaceCheckIn} from "../src/paymaster/WorkplaceCheckIn.sol";

contract MetaTxTest is Test {
    GembaForwarder forwarder;
    WorkplaceCheckIn target;

    uint256 employeePk = 0xE49701; // employee's key; never needs GMB
    address employee;
    address relayer = makeAddr("institutionRelayer"); // the sponsoring wallet (holds GMB)

    bytes32 constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 constant REQUEST_TYPEHASH =
        keccak256("ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,uint48 deadline,bytes data)");

    function setUp() public {
        employee = vm.addr(employeePk);
        forwarder = new GembaForwarder();
        target = new WorkplaceCheckIn(address(forwarder));
        vm.deal(relayer, 100 ether); // institution funds its relayer
        // employee holds NOTHING
        assertEq(employee.balance, 0);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes("GembaForwarder")),
                keccak256(bytes("1")),
                block.chainid,
                address(forwarder)
            )
        );
    }

    function _signCheckIn(uint256 pk, uint48 deadline)
        internal
        view
        returns (ERC2771Forwarder.ForwardRequestData memory req)
    {
        address from = vm.addr(pk);
        bytes memory data = abi.encodeCall(WorkplaceCheckIn.checkIn, ());
        uint256 gas = 200000;
        uint256 nonce = forwarder.nonces(from);

        bytes32 structHash =
            keccak256(abi.encode(REQUEST_TYPEHASH, from, address(target), uint256(0), gas, nonce, deadline, keccak256(data)));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);

        req = ERC2771Forwarder.ForwardRequestData({
            from: from,
            to: address(target),
            value: 0,
            gas: gas,
            deadline: deadline,
            data: data,
            signature: abi.encodePacked(r, s, v)
        });
    }

    /// The core demo: an employee with 0 GMB gets a successful, correctly-attributed
    /// transaction whose gas the relayer pays.
    function test_SponsoredCheckIn_EmployeeHoldsNothing() public {
        ERC2771Forwarder.ForwardRequestData memory req = _signCheckIn(employeePk, uint48(block.timestamp + 1 hours));
        assertTrue(forwarder.verify(req));

        vm.prank(relayer);
        forwarder.execute(req);

        assertEq(target.checkIns(employee), 1, "attributed to the EMPLOYEE, not the relayer");
        assertEq(target.lastCheckedIn(), employee);
        assertEq(employee.balance, 0, "employee never needed GMB");
        assertEq(target.checkIns(relayer), 0, "relayer is not the actor");
    }

    /// Replay protection: the same signed request cannot be executed twice (nonce).
    function test_ReplayRejected() public {
        ERC2771Forwarder.ForwardRequestData memory req = _signCheckIn(employeePk, uint48(block.timestamp + 1 hours));
        vm.prank(relayer);
        forwarder.execute(req);

        // nonce advanced -> the same request no longer verifies
        assertFalse(forwarder.verify(req));
        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(req);
    }

    /// A request signed by the wrong key is rejected (no forging on behalf of others).
    function test_BadSignatureRejected() public {
        ERC2771Forwarder.ForwardRequestData memory req = _signCheckIn(0xBADBAD, uint48(block.timestamp + 1 hours));
        // claim it is from the employee, but it was signed by another key
        req.from = employee;
        assertFalse(forwarder.verify(req));
        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(req);
    }

    /// An expired request is rejected.
    function test_ExpiredDeadlineRejected() public {
        ERC2771Forwarder.ForwardRequestData memory req = _signCheckIn(employeePk, uint48(block.timestamp + 1));
        vm.warp(block.timestamp + 2);
        assertFalse(forwarder.verify(req));
        vm.prank(relayer);
        vm.expectRevert();
        forwarder.execute(req);
    }

    /// Direct-submit fallback (ADR-011): an employee who holds a little GMB can
    /// always submit the call themselves, attributed to themselves.
    function test_DirectSubmitFallback() public {
        vm.deal(employee, 1 ether);
        vm.prank(employee);
        target.checkIn();
        assertEq(target.checkIns(employee), 1);
    }
}
