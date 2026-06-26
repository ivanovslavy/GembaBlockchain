// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GembaDripFaucet} from "../src/reserves/GembaDripFaucet.sol";

/// End-to-end tests for the mainnet on-chain drip faucet. The whole point is that the
/// per-address cooldown is enforced ON-CHAIN (survives a service restart) and that the
/// faucet cannot be drained below its floor — neither by a relay nor by repeated calls.
contract GembaDripFaucetTest is Test {
    GembaDripFaucet faucet;
    address timelock = makeAddr("timelock"); // owner = governance
    address pauser = makeAddr("pauser");     // EmergencyPause
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address relayer = makeAddr("relayer");

    uint256 constant DRIP = 10 ether;
    uint256 constant COOLDOWN = 1 days;
    uint256 constant FLOOR = 1000 ether;

    function setUp() public {
        GembaDripFaucet impl = new GembaDripFaucet();
        bytes memory data = abi.encodeCall(GembaDripFaucet.initialize, (timelock, pauser, DRIP, COOLDOWN, FLOOR));
        faucet = GembaDripFaucet(payable(address(new ERC1967Proxy(address(impl), data))));
        vm.deal(address(faucet), 2000 ether);
    }

    function test_claim_sendsDrip() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        faucet.claim();
        assertEq(alice.balance, before + DRIP, "alice got the drip");
        assertEq(faucet.lastDrip(alice), block.timestamp);
    }

    // The core property: the cooldown is on-chain, so a second claim fails even though
    // nothing "restarted" — there is no in-memory state to reset.
    function test_cooldown_blocksSecondClaim() public {
        vm.prank(alice);
        faucet.claim();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GembaDripFaucet.CooldownActive.selector, block.timestamp + COOLDOWN));
        faucet.claim();
    }

    function test_cooldown_passesAfterWindow() public {
        vm.prank(alice);
        faucet.claim();
        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(alice);
        faucet.claim(); // exactly at the boundary: allowed
        assertEq(alice.balance, 2 * DRIP);
    }

    // Relayed drip (service pays gas, recipient needs none); cooldown is per recipient,
    // so relaying CANNOT bypass it — the on-chain guard the testnet service lacks.
    function test_dripTo_relayed_cooldownPerRecipient() public {
        vm.prank(relayer);
        faucet.dripTo(bob);
        assertEq(bob.balance, DRIP);
        // relayer tries again immediately for bob -> blocked on-chain
        vm.prank(relayer);
        vm.expectRevert(abi.encodeWithSelector(GembaDripFaucet.CooldownActive.selector, block.timestamp + COOLDOWN));
        faucet.dripTo(bob);
    }

    // The floor cannot be crossed — the faucet refuses to drip into its reserve floor.
    function test_floor_cannotDripBelowMinBalance() public {
        // bring the balance to exactly FLOOR + 1.5 drips so the 2nd drip would cross the floor
        vm.deal(address(faucet), FLOOR + DRIP + (DRIP / 2));
        vm.prank(alice);
        faucet.claim(); // ok: leaves FLOOR + DRIP/2
        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(alice);
        vm.expectRevert(GembaDripFaucet.FaucetExhausted.selector);
        faucet.claim(); // would leave below FLOOR
    }

    function test_pause_haltsDrips() public {
        vm.prank(pauser);
        faucet.pause();
        vm.prank(alice);
        vm.expectRevert(); // Pausable: paused
        faucet.claim();
    }

    function test_setDripParams_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert(); // Ownable: not owner
        faucet.setDripParams(1 ether, 1 hours, 0);

        vm.prank(timelock);
        faucet.setDripParams(1 ether, 1 hours, 0);
        assertEq(faucet.dripAmount(), 1 ether);
        assertEq(faucet.cooldown(), 1 hours);
    }

    // Governance is still the only way funds leave in bulk (inherited release).
    function test_release_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.release(payable(alice), 1 ether);

        uint256 before = bob.balance;
        vm.prank(timelock);
        faucet.release(payable(bob), 5 ether);
        assertEq(bob.balance, before + 5 ether);
    }

    function test_initialize_rejectsZeroDrip() public {
        GembaDripFaucet impl = new GembaDripFaucet();
        bytes memory data = abi.encodeCall(GembaDripFaucet.initialize, (timelock, pauser, 0, COOLDOWN, FLOOR));
        vm.expectRevert(); // ZeroAmount
        new ERC1967Proxy(address(impl), data);
    }
}
