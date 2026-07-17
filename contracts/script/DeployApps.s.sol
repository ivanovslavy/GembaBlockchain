// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GembaTicketing} from "../src/tickets/GembaTicketing.sol";
import {GembaPerks} from "../src/tickets/GembaPerks.sol";
import {IGembaTicketing} from "../src/tickets/GembaPerks.sol";
import {GembaForwarder} from "../src/paymaster/GembaForwarder.sol";
import {WorkplaceCheckIn} from "../src/paymaster/WorkplaceCheckIn.sol";
import {AccessControlNFT} from "../src/access/AccessControlNFT.sol";

/// Deploys the application/reference contracts that were not part of the governance/DEX
/// genesis (R-3): Ticketing, Perks, Paymaster (Forwarder + CheckIn), AccessNFT.
///
/// GMB is sold ONLY via the gembachain.io "Buy GMB" UI → GembaPay backend → GembaPayDispenser
/// (0x0EB2…); the on-chain GembaOnRamp (USDC→GMB) was REMOVED from the codebase entirely
/// (owner decision 2026-07-17) — no public-sale contract exists to deploy.
/// The app contracts (Ticketing/Perks/AccessNFT) are issuer-operated references; admin = deployer.
///
///   FOUNDER_PK=<key> forge script script/DeployApps.s.sol --rpc-url <rpc> --broadcast
contract DeployApps is Script {
    uint256 constant MAX_BONUS = 100_000 ether; // perks max bonus per call (drain bound)

    function run() external {
        uint256 pk = vm.envUint("FOUNDER_PK");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        // CREATE2 + fixed salts (§41): every address = f(deployer, salt, init-code) — nonce-free,
        // so a regenesis redeploy with the same salts + bytecode yields the SAME addresses → dApp
        // configs stay untouched. (Init args must stay identical too — same deployer.)

        // Tickets + Perks (events / employee bonuses) — issuer-operated reference.
        GembaTicketing ticketing = new GembaTicketing{salt: keccak256(bytes("gemba.ticketing.v1"))}(deployer);
        GembaPerks perks = new GembaPerks{salt: keccak256(bytes("gemba.perks.v1"))}(deployer, IGembaTicketing(address(ticketing)), MAX_BONUS);

        // Paymaster (sponsored gas, EIP-2771): forwarder + an example sponsored target.
        GembaForwarder forwarder = new GembaForwarder{salt: keccak256(bytes("gemba.forwarder.v1"))}();
        WorkplaceCheckIn checkin = new WorkplaceCheckIn{salt: keccak256(bytes("gemba.checkin.v1"))}(address(forwarder));

        // Access-control capability NFT (soulbound, no PII) — issuer-operated reference.
        AccessControlNFT access = new AccessControlNFT{salt: keccak256(bytes("gemba.accessnft.v1"))}(deployer);

        vm.stopBroadcast();

        console.log("Ticketing     ", address(ticketing));
        console.log("Perks         ", address(perks));
        console.log("Forwarder     ", address(forwarder));
        console.log("WorkplaceCheckIn", address(checkin));
        console.log("AccessControlNFT", address(access));
    }
}
