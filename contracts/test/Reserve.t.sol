// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {FoundationTreasury} from "../src/reserves/FoundationTreasury.sol";
import {BaseReserve} from "../src/reserves/BaseReserve.sol";

/// A second implementation, used only to prove upgrade authority.
contract FoundationTreasuryV2 is FoundationTreasury {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract ReserveTest is Test {
    FoundationTreasury reserve;
    address timelock = makeAddr("timelock"); // owner = governance (Timelock)
    address pauser = makeAddr("pauser");
    address attacker = makeAddr("attacker");
    address payable recipient = payable(makeAddr("recipient"));

    function setUp() public {
        FoundationTreasury impl = new FoundationTreasury();
        bytes memory data = abi.encodeCall(FoundationTreasury.initialize, (timelock, pauser));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        reserve = FoundationTreasury(payable(address(proxy)));
        vm.deal(address(reserve), 1000 ether); // pre-funded reserve
    }

    function test_OwnerIsTimelock() public view {
        assertEq(reserve.owner(), timelock);
        assertEq(reserve.pauser(), pauser);
    }

    function test_ReleaseOnlyByOwner() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        reserve.release(recipient, 1 ether);

        vm.prank(timelock);
        reserve.release(recipient, 100 ether);
        assertEq(recipient.balance, 100 ether);
        assertEq(address(reserve).balance, 900 ether);
    }

    function test_PauseBlocksRelease() public {
        vm.prank(pauser);
        reserve.pause();
        assertTrue(reserve.paused());

        vm.prank(timelock);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        reserve.release(recipient, 1 ether);

        // governance unpauses, release works again
        vm.prank(timelock);
        reserve.unpause();
        vm.prank(timelock);
        reserve.release(recipient, 1 ether);
        assertEq(recipient.balance, 1 ether);
    }

    function test_OnlyPauserCanPause() public {
        vm.prank(attacker);
        vm.expectRevert(BaseReserve.OnlyPauser.selector);
        reserve.pause();
    }

    function test_GovernanceReplacesPauser() public {
        address newPauser = makeAddr("newPauser");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        reserve.setPauser(newPauser);

        vm.prank(timelock);
        reserve.setPauser(newPauser);
        assertEq(reserve.pauser(), newPauser);
    }

    function test_UpgradeOnlyByOwnerTimelock() public {
        FoundationTreasuryV2 implV2 = new FoundationTreasuryV2();

        // attacker (EOA) cannot upgrade
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        reserve.upgradeToAndCall(address(implV2), "");

        // only the owner (Timelock) can upgrade
        vm.prank(timelock);
        reserve.upgradeToAndCall(address(implV2), "");
        assertEq(FoundationTreasuryV2(payable(address(reserve))).version(), 2);
        // funds survive the upgrade
        assertEq(address(reserve).balance, 1000 ether);
    }

    function test_CannotReinitialize() public {
        vm.expectRevert();
        reserve.initialize(attacker, attacker);
    }

    function test_ReceivesNativeGMB() public {
        // simulates the feesplit 40% inflow (the Cosmos<->EVM seam)
        (bool ok, ) = address(reserve).call{value: 5 ether}("");
        assertTrue(ok);
        assertEq(address(reserve).balance, 1005 ether);
    }
}
