// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {GembaPayDispenser} from "../src/onramp/GembaPayDispenser.sol";
import {GmbCollector} from "../src/onramp/GmbCollector.sol";

/// @notice Reproducible deploy of the Buy-GMB sale channel (owner decision 2026-07-17:
/// GembaOnRamp is REMOVED — the dispenser is the ONLY way GMB is sold):
///   gembachain.io "Buy GMB" UI -> GembaPay backend -> GembaPayDispenser.dispense()
/// plus the GmbCollector (GMB intake for dApp payments via GembaPay).
///
/// The testnet instances (dispenser 0x0EB2…, collector 0x72F7… — see
/// docs/gembapay-gmb-dispenser.md) were deployed by hand; this script makes the pair
/// reproducible from the repo for the MAINNET deploy and any future redeploy.
///
/// CREATE2 + fixed salts (same scheme as DeployGovernance §41): same deployer + salt +
/// bytecode + init args => same address across a regenesis. NOTE: the owner/recipient
/// are CONSTRUCTOR args, so changing them changes the address — decide them before
/// the first mainnet deploy and keep them stable.
///
///   FOUNDER_PK=<deployer key> \
///   DISPENSER_OWNER=0x<GembaPay backend signer> \
///   COLLECTOR_RECIPIENT=0x<where collected GMB drains to> \
///     forge script script/DeployDispenser.s.sol --rpc-url <rpc> --broadcast
///
/// Post-deploy (ceremony checklist): fund() the dispenser from the founder stock,
/// verify both on GembaScan, add both addresses to the GembaVotes exclusion list
/// (docs/mainnet-exclusion-list.md rows 10-11), and set GEMBA_DISPENSER_ADDRESS in
/// the GembaPay backend + blockchain-notifier envs.
contract DeployDispenser is Script {
    function run() external {
        uint256 pk = vm.envUint("FOUNDER_PK");
        // The operational owner (GembaPay backend signer, Ownable2Step) — a documented
        // operational EOA with a rotation plan (mainnet-launch-hardening §D), NOT the
        // deployer by default: the backend signs dispense() automatically, a Timelock
        // cannot.
        address owner = vm.envAddress("DISPENSER_OWNER");
        address payable recipient = payable(vm.envAddress("COLLECTOR_RECIPIENT"));

        vm.startBroadcast(pk);
        GembaPayDispenser dispenser =
            new GembaPayDispenser{salt: keccak256(bytes("gemba.dispenser.v1"))}(owner);
        GmbCollector collector =
            new GmbCollector{salt: keccak256(bytes("gemba.collector.v1"))}(owner, recipient);
        vm.stopBroadcast();

        console2.log("GembaPayDispenser", address(dispenser));
        console2.log("  owner (Ownable2Step)", owner);
        console2.log("GmbCollector", address(collector));
        console2.log("  recipient", recipient);
        console2.log("NEXT: fund() the dispenser, verify on GembaScan, add BOTH to the");
        console2.log("GembaVotes exclusion list (docs/mainnet-exclusion-list.md).");
    }
}
