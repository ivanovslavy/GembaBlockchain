// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GembaVotes} from "../src/governance/GembaVotes.sol";
import {GembaTimelock} from "../src/governance/GembaTimelock.sol";
import {GembaGovernor} from "../src/governance/GembaGovernor.sol";
import {EmergencyPause} from "../src/governance/EmergencyPause.sol";
import {PublicReserve} from "../src/reserves/PublicReserve.sol";
import {FoundationTreasury} from "../src/reserves/FoundationTreasury.sol";
import {DAOReserve} from "../src/reserves/DAOReserve.sol";
import {ContingencyReserve} from "../src/reserves/ContingencyReserve.sol";

/// @notice Re-genesis #5: deploys governance (Votes+Timelock+Governor), the pause-only
/// EmergencyPause (2-of-3 guardians), and the four reserve UUPS proxies owned by the
/// Timelock; then funds each reserve to its EXACT §4.1 amount by broadcasting from the
/// matching genesis EOA. Deployer = founder. Run against the new chain after re-genesis.
contract DeployGovernance is Script {
    // governance settings — env-overridable at deploy.
    //   MAINNET (ceremony runbook): MIN_DELAY=86400 (24h timelock);
    //     leave QUORUM_PCT unset → 40 (the two-tier STANDARD quorum; Critical is the
    //     fixed 51/66 below — the old "QUORUM_PCT=66" note predated the two-tier
    //     system and would wrongly raise the standard tier to 66);
    //     VOTING_PERIOD in BLOCKS: 108000 ≈ 3 days at the measured ~2.4s block time.
    //   testnet: leave unset → the defaults below (5-min timelock, standard 40).
    uint48 constant VOTING_DELAY = 1;        // blocks
    uint256 constant PROPOSAL_THRESHOLD = 0; // any vGMB holder may propose
    // Regenesis 2-tier governance (§9): Standard (quorum 40% / supermajority 51%) for routine
    // proposals; Critical (51% / 66%) for anything touching the Governor/Timelock/staking/treasury
    // (auto-classified on-chain). VOTING_PERIOD default is 86400 blocks ≈ 2.4 days at the
    // measured ~2.4s block time (mainnet sets 108000 ≈ 3 days — see the ceremony note above).
    // Standard quorum is QUORUM_PCT (default 40); critical is CRITICAL_QUORUM (51).
    uint256 constant SUPERMAJORITY = 51;          // standard-tier "For" threshold
    uint256 constant CRITICAL_QUORUM = 51;        // critical-tier quorum
    uint256 constant CRITICAL_SUPERMAJORITY = 66; // critical-tier "For" threshold
    uint256 constant PER_GRANT_CAP = 1000 ether;          // faucet per-grant cap
    uint256 constant FAUCET_EPOCH_CAP = 100_000 ether;    // faucet aggregate cap per window (drain bound)
    uint256 constant FAUCET_EPOCH_LENGTH = 1 days;        // rolling window length

    function run() external {
        uint256 founderPk = vm.envUint("FOUNDER_PK");
        address deployer = vm.addr(founderPk);
        // mainnet hardening (R-5, updated for two-tier governance): set MIN_DELAY=86400 (24h)
        // + VOTING_PERIOD=108000 (~3 days at ~2.4s blocks) in the env for mainnet. Do NOT set
        // QUORUM_PCT — leave it unset → 40 (the STANDARD tier; Critical stays fixed 51/66).
        // The pre-two-tier "QUORUM_PCT=66" instruction is DEAD: setting 66 would trip the
        // constructor check criticalQuorum < standardQuorum and REVERT the deploy.
        // Testnet leaves everything unset → the 300s / 40% / 86400-block defaults below
        // (env reads are inline to keep run()'s stack shallow).

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
                address(new PublicReserve{salt: keccak256(bytes("gemba.publicreserve.impl.v1"))}()),
                abi.encodeCall(
                    PublicReserve.initialize,
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

        // Votes: exclude the four reserve contracts (finding #10) + any EXCLUDE_EXTRA addresses.
        // For MAINNET pass every pre-seeded holder via EXCLUDE_EXTRA — the founder EOA + each genesis
        // reserve/seed account — so no treasury/pre-seed balance can be wrapped into vGMB votes
        // ("only validators vote at launch", owner 2026-07-17:
        // vGMB is a wrapper, supply starts at 0, so excluding every genesis-seeded address leaves
        // cosmos stake = validators as the only voice until GMB legitimately circulates). Testnet
        // leaves EXCLUDE_EXTRA unset. Governance (Timelock) can add/remove later via setExcluded.
        GembaVotes votes = new GembaVotes{salt: keccak256(bytes("gemba.votes.v1"))}(
            address(timelock), _excludedReserves(faucet, foundation, dao, contingency)
        );

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
        // do NOT fund the EVM PublicReserve contract from an (empty) EOA here. The Cosmos↔EVM faucet
        // seam (module -> contract top-up via governance) is the documented follow-up. The
        // EVM PublicReserve contract is deployed (Timelock-owned) but seeded later via that seam.
        // §4.1 MAINNET amounts (decision 2026-06-29): Foundation 15M, DAO 10M, Contingency 20M
        // (the former 10M circulation pool is folded into Contingency — the old 10M literal here
        // was the pre-2026-06-29 testnet value). Env-overridable for staging reruns only.
        _fund(founderPk, vm.envUint("FOUNDATION_PK"), foundation, vm.envOr("FOUNDATION_FUND", uint256(15_000_000 ether)));
        _fund(founderPk, vm.envUint("DAO_PK"), dao, vm.envOr("DAO_FUND", uint256(10_000_000 ether)));
        _fund(founderPk, vm.envUint("CONTINGENCY_PK"), contingency, vm.envOr("CONTINGENCY_FUND", uint256(20_000_000 ether)));

        console2.log("GembaTimelock", address(timelock));
        console2.log("GembaVotes", address(votes));
        console2.log("GembaGovernor", address(governor));
        console2.log("EmergencyPause", address(pause));
        console2.log("PublicReserve", faucet);
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

    /// @dev The 4 reserve contracts (finding #10) + any EXCLUDE_EXTRA addresses (mainnet: founder
    /// EOA + genesis seed accounts). In its own frame to keep run() off the stack-too-deep limit.
    ///
    /// STRICT parsing on purpose: `vm.envOr(..., new address[](0))` silently swallows a
    /// malformed list and returns the DEFAULT — a typo'd EXCLUDE_EXTRA at the mainnet deploy
    /// would exclude nobody extra and quietly break "only validators vote at launch". So when
    /// the variable is present it goes through `vm.envAddress`, which REVERTS on any bad entry.
    function _excludedReserves(address a, address b, address c, address d)
        internal
        view
        returns (address[] memory list)
    {
        string memory raw = vm.envOr("EXCLUDE_EXTRA", string(""));
        address[] memory extra =
            bytes(raw).length == 0 ? new address[](0) : vm.envAddress("EXCLUDE_EXTRA", ",");
        list = new address[](4 + extra.length);
        list[0] = a;
        list[1] = b;
        list[2] = c;
        list[3] = d;
        for (uint256 i = 0; i < extra.length; i++) list[4 + i] = extra[i];
    }
}
