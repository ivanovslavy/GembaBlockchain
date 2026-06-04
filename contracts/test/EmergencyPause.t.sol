// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {EmergencyPause} from "../src/governance/EmergencyPause.sol";
import {FoundationTreasury} from "../src/reserves/FoundationTreasury.sol";

contract EmergencyPauseTest is Test {
    EmergencyPause guard;
    FoundationTreasury reserve;
    address governance = makeAddr("governance"); // Timelock
    address g1 = makeAddr("g1");
    address g2 = makeAddr("g2");
    address g3 = makeAddr("g3");
    address outsider = makeAddr("outsider");

    function setUp() public {
        address[] memory gs = new address[](3);
        gs[0] = g1;
        gs[1] = g2;
        gs[2] = g3;
        guard = new EmergencyPause(governance, gs, 2); // 2-of-3

        FoundationTreasury impl = new FoundationTreasury();
        bytes memory data = abi.encodeCall(FoundationTreasury.initialize, (governance, address(guard)));
        reserve = FoundationTreasury(payable(address(new ERC1967Proxy(address(impl), data))));
        vm.deal(address(reserve), 100 ether);
    }

    function test_TwoOfThreePauses() public {
        vm.prank(g1);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
        assertFalse(reserve.paused(), "one confirmation is not enough");

        vm.prank(g2);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
        assertTrue(reserve.paused(), "threshold reached -> paused");
    }

    function test_NonGuardianCannotConfirm() public {
        vm.prank(outsider);
        vm.expectRevert(EmergencyPause.OnlyGuardian.selector);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
    }

    function test_GuardianCannotConfirmTwice() public {
        vm.prank(g1);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
        vm.prank(g1);
        vm.expectRevert(EmergencyPause.AlreadyConfirmed.selector);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
    }

    function test_PauseThenUnpauseFreshRound() public {
        vm.prank(g1);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
        vm.prank(g2);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
        assertTrue(reserve.paused());

        vm.prank(g2);
        guard.confirm(address(reserve), EmergencyPause.Op.Unpause);
        vm.prank(g3);
        guard.confirm(address(reserve), EmergencyPause.Op.Unpause);
        assertFalse(reserve.paused());
    }

    function test_GovernanceManagesGuardians() public {
        address g4 = makeAddr("g4");
        vm.prank(outsider);
        vm.expectRevert(EmergencyPause.OnlyGovernance.selector);
        guard.setGuardian(g4, true);

        vm.prank(governance);
        guard.setGuardian(g4, true);
        assertTrue(guard.isGuardian(g4));
        assertEq(guard.guardianCount(), 4);

        vm.prank(governance);
        guard.setThreshold(3);
        assertEq(guard.threshold(), 3);
    }

    function test_CannotRemoveGuardianBelowThreshold() public {
        // 2-of-3; remove two guardians -> would make threshold unsatisfiable
        vm.prank(governance);
        guard.setGuardian(g3, false); // now 2 guardians, threshold 2 ok
        vm.prank(governance);
        vm.expectRevert(EmergencyPause.BadThreshold.selector);
        guard.setGuardian(g2, false); // would be 1 guardian < threshold 2
    }

    /// The guardian has NO function that can move funds — it can only pause/unpause.
    /// This test documents that the reserve balance is untouched by a pause action.
    function test_PauseCannotMoveFunds() public {
        uint256 before = address(reserve).balance;
        vm.prank(g1);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
        vm.prank(g2);
        guard.confirm(address(reserve), EmergencyPause.Op.Pause);
        assertEq(address(reserve).balance, before, "pausing never moves funds");
        assertEq(address(guard).balance, 0, "the guardian never holds funds");
    }
}
