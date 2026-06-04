// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {GembaTicketing} from "../src/tickets/GembaTicketing.sol";

contract TicketingTest is Test {
    GembaTicketing t;
    address admin = makeAddr("admin");
    address organizer = makeAddr("organizer");
    address scanner = makeAddr("scanner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant EVENT = 1;
    uint256 constant PRICE = 2 ether;
    bytes32 ORGANIZER;
    bytes32 REDEEMER;

    function setUp() public {
        t = new GembaTicketing(admin);
        ORGANIZER = t.ORGANIZER_ROLE();
        REDEEMER = t.REDEEMER_ROLE();
        vm.startPrank(admin);
        t.grantRole(ORGANIZER, organizer);
        t.grantRole(REDEEMER, scanner);
        vm.stopPrank();
        vm.prank(organizer);
        t.createEvent(EVENT, 100, PRICE);
    }

    function test_OrganizerIssuesDirect() public {
        vm.prank(organizer);
        t.issue(alice, EVENT, 3);
        assertEq(t.balanceOf(alice, EVENT), 3);
        (, uint256 minted, , , ) = t.events(EVENT);
        assertEq(minted, 3);
    }

    function test_OnlyOrganizerCreatesAndIssues() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ORGANIZER));
        t.issue(alice, EVENT, 1);
    }

    function test_BuyPaysAndMints() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        t.buy{value: 2 * PRICE}(EVENT, 2);
        assertEq(t.balanceOf(alice, EVENT), 2);
        assertEq(t.proceeds(), 2 * PRICE);
        assertEq(address(t).balance, 2 * PRICE);
    }

    function test_BuyWrongPaymentReverts() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(GembaTicketing.WrongPayment.selector);
        t.buy{value: PRICE}(EVENT, 2); // underpays
    }

    function test_ExceedsSupplyReverts() public {
        vm.prank(organizer);
        vm.expectRevert(GembaTicketing.ExceedsSupply.selector);
        t.issue(alice, EVENT, 101);
    }

    function test_InactiveEventCannotBeBought() public {
        vm.prank(organizer);
        t.setEventActive(EVENT, false);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(GembaTicketing.EventInactive.selector);
        t.buy{value: PRICE}(EVENT, 1);
    }

    function test_SelfRedeem() public {
        vm.prank(organizer);
        t.issue(alice, EVENT, 1);
        vm.prank(alice);
        t.redeem(EVENT);
        assertEq(t.balanceOf(alice, EVENT), 0);
    }

    function test_ScannerRedeemsHolderTicket() public {
        vm.prank(organizer);
        t.issue(alice, EVENT, 1);
        vm.prank(scanner);
        t.redeemFrom(alice, EVENT);
        assertEq(t.balanceOf(alice, EVENT), 0);
    }

    function test_RedeemWithoutTicketReverts() public {
        vm.prank(bob);
        vm.expectRevert(GembaTicketing.NotTicketHolder.selector);
        t.redeem(EVENT);
    }

    function test_OnlyRedeemerRole() public {
        vm.prank(organizer);
        t.issue(alice, EVENT, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, bob, REDEEMER));
        t.redeemFrom(alice, EVENT);
    }

    function test_AdminWithdrawsProceeds() public {
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        t.buy{value: 2 * PRICE}(EVENT, 2);

        vm.prank(admin);
        t.withdrawProceeds(admin, 2 * PRICE);
        assertEq(admin.balance, 2 * PRICE);
        assertEq(t.proceeds(), 0);
    }

    function test_WithdrawAboveProceedsReverts() public {
        vm.prank(admin);
        vm.expectRevert(GembaTicketing.InsufficientBalance.selector);
        t.withdrawProceeds(admin, 1 ether);
    }
}
