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
    // live testnet
    address constant TIMELOCK = 0x4117ae45e76A77D1d54af57642aefD02A184cf90;
    address constant USDC = 0x131f3087ecabA6f7ae91439DDaF70f4269D4b9Ef; // test USD Coin
    uint256 constant MAX_BONUS = 100_000 ether; // perks max bonus per call (drain bound)

    function run() external {
        uint256 pk = vm.envUint("FOUNDER_PK");
        address deployer = vm.addr(pk);
        vm.startBroadcast(pk);

        // OnRamp — owner = Timelock (governance-controlled; AU-4). publicSaleEnabled is false
        // by default (no public sale by design, §2/Phase 6).
        GembaOnRamp onramp = new GembaOnRamp(TIMELOCK, IERC20(USDC));

        // Tickets + Perks (events / employee bonuses) — issuer-operated reference.
        GembaTicketing ticketing = new GembaTicketing(deployer);
        GembaPerks perks = new GembaPerks(deployer, IGembaTicketing(address(ticketing)), MAX_BONUS);

        // Paymaster (sponsored gas, EIP-2771): forwarder + an example sponsored target.
        GembaForwarder forwarder = new GembaForwarder();
        WorkplaceCheckIn checkin = new WorkplaceCheckIn(address(forwarder));

        // Access-control capability NFT (soulbound, no PII) — issuer-operated reference.
        AccessControlNFT access = new AccessControlNFT(deployer);

        vm.stopBroadcast();

        console.log("OnRamp        ", address(onramp), "(owner=Timelock)");
        console.log("Ticketing     ", address(ticketing));
        console.log("Perks         ", address(perks));
        console.log("Forwarder     ", address(forwarder));
        console.log("WorkplaceCheckIn", address(checkin));
        console.log("AccessControlNFT", address(access));
    }
}
