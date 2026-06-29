// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PublicReserve} from "../src/reserves/PublicReserve.sol";

contract PublicReserveTest is Test {
    PublicReserve faucet;
    address timelock = makeAddr("timelock");
    address pauser = makeAddr("pauser");
    address granter = makeAddr("granter");
    address attacker = makeAddr("attacker");
    address payable inst = payable(makeAddr("institution"));
    uint256 cap = 1000 ether;

    function setUp() public {
        PublicReserve impl = new PublicReserve();
        bytes memory data = abi.encodeCall(PublicReserve.initialize, (timelock, pauser, granter, cap, 0, 0));
        faucet = PublicReserve(payable(address(new ERC1967Proxy(address(impl), data))));
        vm.deal(address(faucet), 100000 ether);
    }

    function test_GranterGrantsWithinCap() public {
        vm.prank(granter);
        faucet.grant(inst, 800 ether);
        assertEq(inst.balance, 800 ether);
        assertEq(faucet.totalGranted(), 800 ether);
    }

    function test_GrantAboveCapReverts() public {
        vm.prank(granter);
        vm.expectRevert(PublicReserve.AboveCap.selector);
        faucet.grant(inst, cap + 1);
    }

    function test_OnlyGranterOrOwnerGrants() public {
        vm.prank(attacker);
        vm.expectRevert(PublicReserve.OnlyGranter.selector);
        faucet.grant(inst, 1 ether);

        // owner (governance) may also grant within the cap
        vm.prank(timelock);
        faucet.grant(inst, 10 ether);
        assertEq(inst.balance, 10 ether);
    }

    function test_LargeGrantViaOwnerRelease() public {
        // above-cap disbursement uses release(): owner (Timelock) only, uncapped
        vm.prank(timelock);
        faucet.release(inst, 50000 ether);
        assertEq(inst.balance, 50000 ether);
    }

    function test_PauseBlocksGrant() public {
        vm.prank(pauser);
        faucet.pause();
        vm.prank(granter);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        faucet.grant(inst, 1 ether);
    }

    function test_GovernanceTunesCapAndGranter() public {
        vm.prank(timelock);
        faucet.setPerGrantCap(5 ether);
        vm.prank(granter);
        vm.expectRevert(PublicReserve.AboveCap.selector);
        faucet.grant(inst, 6 ether);

        address newGranter = makeAddr("newGranter");
        vm.prank(timelock);
        faucet.setGranter(newGranter);
        vm.prank(granter);
        vm.expectRevert(PublicReserve.OnlyGranter.selector);
        faucet.grant(inst, 1 ether);
    }

    function test_NonOwnerCannotTuneCap() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        faucet.setPerGrantCap(1);
    }

    // --- audit finding #3: rolling-window cap bounds a compromised granter ---

    function test_EpochCapBoundsAggregateGrants() public {
        vm.prank(timelock);
        faucet.setEpochLimit(1500 ether, 1 days); // aggregate cap per rolling day
        vm.prank(granter);
        faucet.grant(inst, 1000 ether); // single call at the per-grant cap
        vm.prank(granter);
        vm.expectRevert(PublicReserve.AboveEpochCap.selector);
        faucet.grant(inst, 600 ether); // 1000 + 600 > 1500 window cap
        assertEq(inst.balance, 1000 ether);
        // window resets after epochLength
        vm.warp(block.timestamp + 1 days);
        vm.prank(granter);
        faucet.grant(inst, 600 ether);
        assertEq(inst.balance, 1600 ether);
    }

    function test_EpochCapStopsDrainAcrossManyCalls() public {
        vm.prank(timelock);
        faucet.setEpochLimit(1000 ether, 1 days); // 1000 GMB/day aggregate
        vm.prank(granter);
        faucet.grant(inst, 1000 ether);
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(granter);
            vm.expectRevert(PublicReserve.AboveEpochCap.selector);
            faucet.grant(inst, 1 ether); // hard daily bound, not per-call only
        }
        assertEq(inst.balance, 1000 ether);
    }

    function test_OnlyOwnerSetsEpochLimit() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        faucet.setEpochLimit(1, 1);
    }

    // audit finding #6: a non-zero cap with a zero window would void the aggregate bound
    function test_InvalidEpochConfigReverts() public {
        vm.prank(timelock);
        vm.expectRevert(PublicReserve.InvalidEpochConfig.selector);
        faucet.setEpochLimit(1000 ether, 0);
    }
}
