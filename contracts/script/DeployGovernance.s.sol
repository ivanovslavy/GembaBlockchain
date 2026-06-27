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
    // governance settings. Testnet uses short delays + a 50% quorum; MAINNET hardens to a
    // 24h timelock + 66% quorum (CLAUDE.md §7, R-5). Both are env-overridable at deploy:
    //   MAINNET: MIN_DELAY=86400  QUORUM_PCT=66   (24h timelock, 66% quorum)
    //   testnet: leave unset → the defaults below (5-min timelock, 50% quorum)
    uint48 constant VOTING_DELAY = 1;        // blocks
    uint256 constant PROPOSAL_THRESHOLD = 0; // any vGMB holder may propose
    // Regenesis 2-tier governance (§9): Standard (quorum 40% / supermajority 51%) for routine
    // proposals; Critical (51% / 66%) for anything touching the Governor/Timelock/staking/treasury
    // (auto-classified on-chain). Voting period defaults to ~3 days at ~3s blocks (env-overridable
    // for staging). Standard quorum is QUORUM_PCT (default 40); critical is CRITICAL_QUORUM (51).
    uint256 constant SUPERMAJORITY = 51;          // standard-tier "For" threshold
    uint256 constant CRITICAL_QUORUM = 51;        // critical-tier quorum
    uint256 constant CRITICAL_SUPERMAJORITY = 66; // critical-tier "For" threshold
    uint256 constant PER_GRANT_CAP = 1000 ether;          // faucet per-grant cap
    uint256 constant FAUCET_EPOCH_CAP = 100_000 ether;    // faucet aggregate cap per window (drain bound)
    uint256 constant FAUCET_EPOCH_LENGTH = 1 days;        // rolling window length

    function run() external {
        uint256 founderPk = vm.envUint("FOUNDER_PK");
        address deployer = vm.addr(founderPk);
        // mainnet hardening (R-5): set MIN_DELAY=86400 (24h) + QUORUM_PCT=66 in the env for
        // mainnet; testnet leaves them unset → the 300s / 50% defaults below (read inline to
        // keep run()'s stack shallow).

        // --- deploy governance + reserves (founder) ---
        vm.startBroadcast(founderPk);

        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution: anyone executes after the delay
        // CREATE2 + fixed salts (§41): all protocol addresses survive a regenesis (same salt +
        // bytecode + init args => same address). The deployer (founder) + the canonical CREATE2
        // factory are constant, so re-running this script on the fresh chain reproduces every CA.
        GembaTimelock timelock = new GembaTimelock{salt: keccak256(bytes("gemba.timelock.v1"))}(vm.envOr("MIN_DELAY", uint256(300)), proposers, executors, deployer);

        // EmergencyPause: 3 governance-elected guardians, 2-of-3 to pause (pause-only).
        address[] memory guardians = new address[](3);
        guardians[0] = vm.envAddress("GUARDIAN1");
        guardians[1] = vm.envAddress("GUARDIAN2");
        guardians[2] = vm.envAddress("GUARDIAN3");
        EmergencyPause pause = new EmergencyPause{salt: keccak256(bytes("gemba.emergencypause.v1"))}(address(timelock), guardians, 2);

        // reserves: UUPS proxies, owner = Timelock, pauser = EmergencyPause.
        // Deployed BEFORE GembaVotes so their addresses can be excluded at genesis (finding #10).
        address faucet = address(
            new ERC1967Proxy{salt: keccak256(bytes("gemba.faucet.v1"))}(
                address(new Faucet{salt: keccak256(bytes("gemba.faucet.impl.v1"))}()),
                abi.encodeCall(
                    Faucet.initialize,
                    (address(timelock), address(pause), deployer, PER_GRANT_CAP, FAUCET_EPOCH_CAP, FAUCET_EPOCH_LENGTH)
                )
            )
        );
        address foundation = address(
            new ERC1967Proxy{salt: keccak256(bytes("gemba.foundation.v1"))}(
                address(new FoundationTreasury{salt: keccak256(bytes("gemba.foundation.impl.v1"))}()),
                abi.encodeCall(FoundationTreasury.initialize, (address(timelock), address(pause)))
            )
        );
        address dao = address(
            new ERC1967Proxy{salt: keccak256(bytes("gemba.dao.v1"))}(
                address(new DAOReserve{salt: keccak256(bytes("gemba.dao.impl.v1"))}()),
                abi.encodeCall(DAOReserve.initialize, (address(timelock), address(pause)))
            )
        );
        address contingency = address(
            new ERC1967Proxy{salt: keccak256(bytes("gemba.contingency.v1"))}(
                address(new ContingencyReserve{salt: keccak256(bytes("gemba.contingency.impl.v1"))}()),
                abi.encodeCall(ContingencyReserve.initialize, (address(timelock), address(pause)))
            )
        );

        // Votes: exclude the four reserve contracts from voting at genesis (finding #10).
        address[] memory excludedReserves = new address[](4);
        excludedReserves[0] = faucet;
        excludedReserves[1] = foundation;
        excludedReserves[2] = dao;
        excludedReserves[3] = contingency;
        GembaVotes votes = new GembaVotes{salt: keccak256(bytes("gemba.votes.v1"))}(address(timelock), excludedReserves);

        GembaGovernor governor = new GembaGovernor{salt: keccak256(bytes("gemba.governor.v1"))}(
            IVotes(address(votes)), timelock, VOTING_DELAY, uint32(vm.envOr("VOTING_PERIOD", uint256(86400))),
            PROPOSAL_THRESHOLD, vm.envOr("QUORUM_PCT", uint256(40)), SUPERMAJORITY, CRITICAL_QUORUM, CRITICAL_SUPERMAJORITY
        );

        // wire: Governor proposes/cancels; the deployer renounces the timelock admin so
        // only governance (propose -> vote -> queue -> anyone executes) controls it.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        // --- fund each reserve to its exact §4.1 amount, from the matching genesis EOA ---
        // The founder sponsors a tiny gas buffer first, so each reserve EOA (which holds
        // EXACTLY its §4.1 amount) can transfer that full amount and the contract ends up
        // holding exactly its %.
        // REGENESIS NOTE (2026-06-27): the faucet's 30M lives in the Cosmos faucet MODULE
        // account (where the 60/40 feesplit + slash redirects accrue), NOT in an EOA — so we
        // do NOT fund the EVM Faucet contract from an (empty) EOA here. The Cosmos↔EVM faucet
        // seam (module -> contract top-up via governance) is the documented follow-up. The
        // EVM Faucet contract is deployed (Timelock-owned) but seeded later via that seam.
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
