// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {GembaTicketing} from "../src/tickets/GembaTicketing.sol";
import {GembaPerks, IGembaTicketing} from "../src/tickets/GembaPerks.sol";

/// @notice Live devnet demo of Phase 8 (Ticketing + perks). The organizer/employer
/// (OPERATOR_PK) issues a ticket directly, the attendee (ATTENDEE_PK) buys one with
/// GMB, the employer pays a GMB bonus + grants a perk ticket, and the attendee
/// redeems (checks in). Env: OPERATOR_PK, ATTENDEE_PK (both need a little GMB).
contract TicketingDemo is Script {
    uint256 constant EVENT = 1;
    uint256 constant PRICE = 5 ether;

    function run() external {
        uint256 opPk = vm.envUint("OPERATOR_PK");
        uint256 attPk = vm.envUint("ATTENDEE_PK");
        address operator = vm.addr(opPk);
        address attendee = vm.addr(attPk);
        uint256 gmbStart = attendee.balance; // before any bonus/payment

        // employer/organizer deploys and configures
        vm.startBroadcast(opPk);
        GembaTicketing tk = new GembaTicketing(operator);
        GembaPerks perks = new GembaPerks(operator, IGembaTicketing(address(tk)), 1000 ether);
        tk.grantRole(tk.ORGANIZER_ROLE(), operator);
        tk.grantRole(tk.ORGANIZER_ROLE(), address(perks)); // perks may issue perk tickets
        tk.grantRole(tk.REDEEMER_ROLE(), operator);
        perks.grantRole(perks.DISTRIBUTOR_ROLE(), operator);
        tk.createEvent(EVENT, 100, PRICE);
        tk.issue(attendee, EVENT, 1); // (1) direct issue (comp ticket)
        (bool ok, ) = address(perks).call{value: 10000 ether}(""); // fund perks pool
        require(ok, "fund failed");
        perks.payBonus(attendee, 100 ether); // (3a) employee GMB bonus
        perks.grantPerk(attendee, EVENT); // (3b) perk ticket
        vm.stopBroadcast();

        console.log("after issue + perk, attendee tickets:", tk.balanceOf(attendee, EVENT)); // 2

        // attendee buys a ticket with GMB
        vm.broadcast(attPk);
        tk.buy{value: PRICE}(EVENT, 1); // (2) paid buy
        console.log("after buy, attendee tickets:", tk.balanceOf(attendee, EVENT)); // 3

        // attendee redeems (check-in)
        vm.broadcast(attPk);
        tk.redeem(EVENT); // (4) usage
        console.log("after redeem, attendee tickets:", tk.balanceOf(attendee, EVENT)); // 2

        console.log("ticketing proceeds (GMB):", tk.proceeds() / 1e18);
        // net = +100 bonus - 5 ticket - gas (~ +95)
        console.log("attendee GMB net delta:", (int256(attendee.balance) - int256(gmbStart)) / 1e18);
    }
}
