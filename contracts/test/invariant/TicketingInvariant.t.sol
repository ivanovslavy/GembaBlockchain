// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GembaTicketing} from "../../src/tickets/GembaTicketing.sol";

/// Random issue/buy/redeem sequences against one event. Invariant: the event's
/// `minted` never exceeds `maxSupply` — the cap can never be breached, however the
/// callers mix direct issues, paid buys, and redeems.
contract TicketingHandler is Test {
    GembaTicketing public t;
    uint256 public constant EVENT = 1;
    uint256 public constant MAX = 1000;
    uint256 public constant PRICE = 1 ether;
    address organizer;
    address[3] buyers;

    constructor(GembaTicketing t_, address organizer_) {
        t = t_;
        organizer = organizer_;
        buyers = [makeAddr("b1"), makeAddr("b2"), makeAddr("b3")];
    }

    function issue(uint256 buyerSeed, uint256 amount) public {
        amount = bound(amount, 1, 50);
        address to = buyers[buyerSeed % buyers.length];
        vm.prank(organizer);
        try t.issue(to, EVENT, amount) {} catch {}
    }

    function buy(uint256 buyerSeed, uint256 amount) public {
        amount = bound(amount, 1, 50);
        address b = buyers[buyerSeed % buyers.length];
        vm.deal(b, b.balance + amount * PRICE);
        vm.prank(b);
        try t.buy{value: amount * PRICE}(EVENT, amount) {} catch {}
    }

    function redeem(uint256 buyerSeed) public {
        address b = buyers[buyerSeed % buyers.length];
        vm.prank(b);
        try t.redeem(EVENT) {} catch {}
    }
}

contract TicketingInvariantTest is Test {
    GembaTicketing t;
    TicketingHandler handler;

    function setUp() public {
        t = new GembaTicketing(address(this));
        address organizer = makeAddr("organizer");
        t.grantRole(t.ORGANIZER_ROLE(), organizer);
        vm.prank(organizer);
        t.createEvent(1, 1000, 1 ether);
        handler = new TicketingHandler(t, organizer);
        targetContract(address(handler));
    }

    function invariant_MintedNeverExceedsMaxSupply() public view {
        (uint256 maxSupply, uint256 minted, , , ) = t.events(1);
        assertLe(minted, maxSupply);
    }
}
