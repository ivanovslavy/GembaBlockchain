// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GembaVotes} from "../src/governance/GembaVotes.sol";
import {GembaTimelock} from "../src/governance/GembaTimelock.sol";
import {GembaGovernor} from "../src/governance/GembaGovernor.sol";
import {EmergencyPause} from "../src/governance/EmergencyPause.sol";
import {Faucet} from "../src/reserves/Faucet.sol";
import {FoundationTreasury} from "../src/reserves/FoundationTreasury.sol";
import {DAOReserve} from "../src/reserves/DAOReserve.sol";
import {ContingencyReserve} from "../src/reserves/ContingencyReserve.sol";

/// @notice Re-genesis #5: deploys governance (Votes+Timelock+Governor), the pause-only
/// EmergencyPause (2-of-3 guardians), and the four reserve UUPS proxies owned by the
/// Timelock; then funds each reserve to its EXACT §4.1 amount by broadcasting from the
/// matching genesis EOA. Deployer = founder. Run against the new chain after re-genesis.
contract DeployGovernance is Script {
    // governance settings (testnet — short delays; §7 high quorum + supermajority)
    uint256 constant MIN_DELAY = 300;        // 5-min timelock (raise via governance on mainnet)
    uint48 constant VOTING_DELAY = 1;        // blocks
    uint32 constant VOTING_PERIOD = 600;     // blocks (~20 min @ 2s)
    uint256 constant PROPOSAL_THRESHOLD = 0; // any vGMB holder may propose
    uint256 constant QUORUM = 50;            // 50% of vGMB (treasury bar)
    uint256 constant SUPERMAJORITY = 66;     // 66% to pass (§7)
    uint256 constant PER_GRANT_CAP = 1000 ether; // faucet per-grant cap

    function run() external {
        uint256 founderPk = vm.envUint("FOUNDER_PK");
        address deployer = vm.addr(founderPk);

        // --- deploy governance + reserves (founder) ---
        vm.startBroadcast(founderPk);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution: anyone executes after the delay
        GembaTimelock timelock = new GembaTimelock(MIN_DELAY, proposers, executors, deployer);

        GembaVotes votes = new GembaVotes(address(timelock));
        GembaGovernor governor = new GembaGovernor(
            IVotes(address(votes)), timelock, VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD, QUORUM, SUPERMAJORITY
        );

        // wire: Governor proposes/cancels; the deployer renounces the timelock admin so
        // only governance (propose -> vote -> queue -> anyone executes) controls it.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        // EmergencyPause: 3 governance-elected guardians, 2-of-3 to pause (pause-only).
        address[] memory guardians = new address[](3);
        guardians[0] = vm.envAddress("GUARDIAN1");
        guardians[1] = vm.envAddress("GUARDIAN2");
        guardians[2] = vm.envAddress("GUARDIAN3");
        EmergencyPause pause = new EmergencyPause(address(timelock), guardians, 2);

        // reserves: UUPS proxies, owner = Timelock, pauser = EmergencyPause
        address faucet = address(
            new ERC1967Proxy(
                address(new Faucet()),
                abi.encodeCall(Faucet.initialize, (address(timelock), address(pause), deployer, PER_GRANT_CAP))
            )
        );
        address foundation = address(
            new ERC1967Proxy(
                address(new FoundationTreasury()),
                abi.encodeCall(FoundationTreasury.initialize, (address(timelock), address(pause)))
            )
        );
        address dao = address(
            new ERC1967Proxy(
                address(new DAOReserve()),
                abi.encodeCall(DAOReserve.initialize, (address(timelock), address(pause)))
            )
        );
        address contingency = address(
            new ERC1967Proxy(
                address(new ContingencyReserve()),
                abi.encodeCall(ContingencyReserve.initialize, (address(timelock), address(pause)))
            )
        );
        vm.stopBroadcast();

        // --- fund each reserve to its exact §4.1 amount, from the matching genesis EOA ---
        // The founder sponsors a tiny gas buffer first, so each reserve EOA (which holds
        // EXACTLY its §4.1 amount) can transfer that full amount and the contract ends up
        // holding exactly its %.
        _fund(founderPk, vm.envUint("FAUCETRESERVE_PK"), faucet, 30_000_000 ether);
        _fund(founderPk, vm.envUint("FOUNDATION_PK"), foundation, 15_000_000 ether);
        _fund(founderPk, vm.envUint("DAO_PK"), dao, 10_000_000 ether);
        _fund(founderPk, vm.envUint("CONTINGENCY_PK"), contingency, 10_000_000 ether);

        console2.log("GembaTimelock", address(timelock));
        console2.log("GembaVotes", address(votes));
        console2.log("GembaGovernor", address(governor));
        console2.log("EmergencyPause", address(pause));
        console2.log("Faucet", faucet);
        console2.log("FoundationTreasury", foundation);
        console2.log("DAOReserve", dao);
        console2.log("ContingencyReserve", contingency);
    }

    function _fund(uint256 founderPk, uint256 eoaPk, address reserve, uint256 amount) internal {
        address eoa = vm.addr(eoaPk);
        vm.startBroadcast(founderPk);
        (bool g, ) = eoa.call{value: 0.1 ether}(""); // gas buffer (founder-sponsored)
        require(g, "gas buffer failed");
        vm.stopBroadcast();
        vm.startBroadcast(eoaPk);
        (bool ok, ) = reserve.call{value: amount}("");
        require(ok, "fund failed");
        vm.stopBroadcast();
    }
}
