// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Faucet} from "../src/reserves/Faucet.sol";

contract FaucetTest is Test {
    Faucet faucet;
    address timelock = makeAddr("timelock");
    address pauser = makeAddr("pauser");
    address granter = makeAddr("granter");
    address attacker = makeAddr("attacker");
    address payable inst = payable(makeAddr("institution"));
    uint256 cap = 1000 ether;

    function setUp() public {
        Faucet impl = new Faucet();
        bytes memory data = abi.encodeCall(Faucet.initialize, (timelock, pauser, granter, cap));
        faucet = Faucet(payable(address(new ERC1967Proxy(address(impl), data))));
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
        vm.expectRevert(Faucet.AboveCap.selector);
        faucet.grant(inst, cap + 1);
    }

    function test_OnlyGranterOrOwnerGrants() public {
        vm.prank(attacker);
        vm.expectRevert(Faucet.OnlyGranter.selector);
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
        vm.expectRevert(Faucet.AboveCap.selector);
        faucet.grant(inst, 6 ether);

        address newGranter = makeAddr("newGranter");
        vm.prank(timelock);
        faucet.setGranter(newGranter);
        vm.prank(granter);
        vm.expectRevert(Faucet.OnlyGranter.selector);
        faucet.grant(inst, 1 ether);
    }

    function test_NonOwnerCannotTuneCap() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        faucet.setPerGrantCap(1);
    }
}
