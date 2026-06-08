// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {GembaTicketing} from "../src/tickets/GembaTicketing.sol";
import {GembaPerks, IGembaTicketing} from "../src/tickets/GembaPerks.sol";

contract PerksTest is Test {
    GembaTicketing ticketing;
    GembaPerks perks;
    address admin = makeAddr("admin");
    address distributor = makeAddr("distributor"); // institution HR/ops
    address employee = makeAddr("employee");
    address other = makeAddr("other");
    uint256 constant PERK_EVENT = 7;
    uint256 constant MAX_BONUS = 1000 ether;
    bytes32 DISTRIBUTOR;

    function setUp() public {
        ticketing = new GembaTicketing(admin);
        perks = new GembaPerks(admin, IGembaTicketing(address(ticketing)), MAX_BONUS);
        DISTRIBUTOR = perks.DISTRIBUTOR_ROLE();

        vm.startPrank(admin);
        // perks contract may issue perk tickets; create the perk event
        ticketing.grantRole(ticketing.ORGANIZER_ROLE(), address(perks));
        ticketing.grantRole(ticketing.ORGANIZER_ROLE(), admin);
        ticketing.createEvent(PERK_EVENT, 1000, 0);
        // appoint the distributor
        perks.grantRole(DISTRIBUTOR, distributor);
        vm.stopPrank();

        vm.deal(address(perks), 100000 ether); // institution funds the pool
    }

    function test_PayBonus() public {
        vm.prank(distributor);
        perks.payBonus(employee, 500 ether);
        assertEq(employee.balance, 500 ether);
        assertEq(address(perks).balance, 99500 ether);
    }

    function test_PayBonusBatch() public {
        address[] memory emps = new address[](2);
        uint256[] memory amts = new uint256[](2);
        emps[0] = employee;
        emps[1] = other;
        amts[0] = 100 ether;
        amts[1] = 200 ether;
        vm.prank(distributor);
        perks.payBonusBatch(emps, amts);
        assertEq(employee.balance, 100 ether);
        assertEq(other.balance, 200 ether);
    }

    function test_BonusAboveCapReverts() public {
        vm.prank(distributor);
        vm.expectRevert(GembaPerks.AboveMaxBonus.selector);
        perks.payBonus(employee, MAX_BONUS + 1);
    }

    function test_OnlyDistributorPaysBonus() public {
        vm.prank(other);
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, DISTRIBUTOR));
        perks.payBonus(employee, 1 ether);
    }

    function test_GrantPerkTicket() public {
        vm.prank(distributor);
        perks.grantPerk(employee, PERK_EVENT);
        assertEq(ticketing.balanceOf(employee, PERK_EVENT), 1, "employee received the perk ticket");
    }

    function test_BatchLengthMismatchReverts() public {
        address[] memory emps = new address[](2);
        uint256[] memory amts = new uint256[](1);
        vm.prank(distributor);
        vm.expectRevert(GembaPerks.LengthMismatch.selector);
        perks.payBonusBatch(emps, amts);
    }

    function test_AdminWithdraws() public {
        vm.prank(admin);
        perks.withdraw(admin, 1000 ether);
        assertEq(admin.balance, 1000 ether);
    }

    // audit finding #8: one reverting recipient must not block the rest of the batch
    function test_BatchSkipsRevertingRecipient() public {
        RevertingReceiver bad = new RevertingReceiver();
        address[] memory emps = new address[](3);
        emps[0] = employee;
        emps[1] = address(bad);
        emps[2] = other;
        uint256[] memory amts = new uint256[](3);
        amts[0] = 100 ether;
        amts[1] = 100 ether;
        amts[2] = 100 ether;
        vm.prank(distributor);
        perks.payBonusBatch(emps, amts); // does NOT revert despite the bad middle entry
        assertEq(employee.balance, 100 ether, "good recipient before the bad one paid");
        assertEq(other.balance, 100 ether, "good recipient after the bad one still paid");
        assertEq(address(bad).balance, 0, "reverting recipient skipped, not paid");
    }
}

contract RevertingReceiver {
    receive() external payable {
        revert("nope");
    }
}
