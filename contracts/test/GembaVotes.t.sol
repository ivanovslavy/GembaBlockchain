// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GembaVotes} from "../src/governance/GembaVotes.sol";

contract GembaVotesTest is Test {
    GembaVotes votes;
    address governance = address(0x600);
    address alice = address(0xA11CE);
    address reserve = address(0xBEEF); // a "reserve" contract, to be excluded

    function setUp() public {
        votes = new GembaVotes(governance, new address[](0));
        vm.deal(alice, 1000 ether);
    }

    function test_WrapMintsVotingPower() public {
        vm.prank(alice);
        votes.depositFor{value: 100 ether}(alice);
        assertEq(votes.balanceOf(alice), 100 ether);
        vm.prank(alice);
        votes.delegate(alice);
        assertEq(votes.getVotes(alice), 100 ether);
        assertEq(address(votes).balance, 100 ether, "contract holds the wrapped native GMB");
    }

    function test_UnwrapReturnsNativeGMB() public {
        vm.startPrank(alice);
        votes.depositFor{value: 100 ether}(alice);
        votes.withdrawTo(alice, 40 ether);
        vm.stopPrank();
        assertEq(votes.balanceOf(alice), 60 ether);
        assertEq(alice.balance, 940 ether); // 1000 - 100 + 40
    }

    function test_ExcludedAddressCannotReceive() public {
        vm.prank(governance);
        votes.setExcluded(reserve, true);

        vm.prank(alice);
        vm.expectRevert(GembaVotes.Excluded.selector);
        votes.depositFor{value: 1 ether}(reserve);
    }

    function test_ExcludedAddressHasZeroVotes() public {
        // give reserve some votes first, then exclude it
        vm.prank(alice);
        votes.depositFor{value: 50 ether}(alice);
        vm.prank(alice);
        votes.transfer(reserve, 50 ether);
        vm.prank(reserve);
        votes.delegate(reserve);
        assertEq(votes.getVotes(reserve), 50 ether);

        vm.prank(governance);
        votes.setExcluded(reserve, true);
        assertEq(votes.getVotes(reserve), 0, "excluded reserve has zero votes");
    }

    function test_OnlyGovernanceSetsExclusion() public {
        vm.prank(alice);
        vm.expectRevert(GembaVotes.OnlyGovernance.selector);
        votes.setExcluded(reserve, true);
    }

    function testFuzz_WrapUnwrapConservesNative(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 1000 ether);
        vm.startPrank(alice);
        votes.depositFor{value: amount}(alice);
        assertEq(address(votes).balance, amount);
        votes.withdrawTo(alice, amount);
        vm.stopPrank();
        assertEq(votes.balanceOf(alice), 0);
        assertEq(address(votes).balance, 0);
        assertEq(alice.balance, 1000 ether);
    }
}
