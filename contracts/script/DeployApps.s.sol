// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GembaOnRamp} from "../src/onramp/GembaOnRamp.sol";
import {GembaTicketing} from "../src/tickets/GembaTicketing.sol";
import {GembaPerks} from "../src/tickets/GembaPerks.sol";
import {IGembaTicketing} from "../src/tickets/GembaPerks.sol";
import {GembaForwarder} from "../src/paymaster/GembaForwarder.sol";
import {WorkplaceCheckIn} from "../src/paymaster/WorkplaceCheckIn.sol";
import {AccessControlNFT} from "../src/access/AccessControlNFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// Deploys the application/reference contracts that were not part of the governance/DEX
/// genesis (R-3): OnRamp, Ticketing, Perks, Paymaster (Forwarder + CheckIn), AccessNFT.
///
/// OnRamp owner = the live Timelock (AU-4 / #5v): the on-ramp holds a pre-funded GMB sale
/// stock, so on mainnet governance — not an EOA — must control it. The app contracts
/// (Ticketing/Perks/AccessNFT) are issuer-operated references; admin = deployer here.
///
///   FOUNDER_PK=<key> forge script script/DeployApps.s.sol --rpc-url <rpc> --broadcast
contract DeployApps is Script {
    // live testnet — regenesis 2026-06-27 CREATE2 Timelock
    address constant TIMELOCK = 0xa75aC1AF72D54e34c5646534F985Be7a172C37C1;
    address constant USDC = 0x131f3087ecabA6f7ae91439DDaF70f4269D4b9Ef; // test USD Coin
    uint256 constant MAX_BONUS = 100_000 ether; // perks max bonus per call (drain bound)

    function run() external {
        uint256 pk = vm.envUint("FOUNDER_PK");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        // CREATE2 + fixed salts (§41): every address = f(deployer, salt, init-code) — nonce-free,
        // so a regenesis redeploy with the same salts + bytecode yields the SAME addresses → dApp
        // configs stay untouched. (Init args must stay identical too — same TIMELOCK/USDC/deployer.)
        GembaOnRamp onramp = new GembaOnRamp{salt: keccak256(bytes("gemba.onramp.v1"))}(TIMELOCK, IERC20(USDC));

        // Tickets + Perks (events / employee bonuses) — issuer-operated reference.
        GembaTicketing ticketing = new GembaTicketing{salt: keccak256(bytes("gemba.ticketing.v1"))}(deployer);
        GembaPerks perks = new GembaPerks{salt: keccak256(bytes("gemba.perks.v1"))}(deployer, IGembaTicketing(address(ticketing)), MAX_BONUS);

        // Paymaster (sponsored gas, EIP-2771): forwarder + an example sponsored target.
        GembaForwarder forwarder = new GembaForwarder{salt: keccak256(bytes("gemba.forwarder.v1"))}();
        WorkplaceCheckIn checkin = new WorkplaceCheckIn{salt: keccak256(bytes("gemba.checkin.v1"))}(address(forwarder));

        // Access-control capability NFT (soulbound, no PII) — issuer-operated reference.
        AccessControlNFT access = new AccessControlNFT{salt: keccak256(bytes("gemba.accessnft.v1"))}(deployer);

        vm.stopBroadcast();

        console.log("OnRamp        ", address(onramp), "(owner=Timelock)");
        console.log("Ticketing     ", address(ticketing));
        console.log("Perks         ", address(perks));
        console.log("Forwarder     ", address(forwarder));
        console.log("WorkplaceCheckIn", address(checkin));
        console.log("AccessControlNFT", address(access));
    }
}
