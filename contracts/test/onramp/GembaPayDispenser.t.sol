// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GembaPayDispenser} from "../../src/onramp/GembaPayDispenser.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/*//////////////////////////////////////////////////////////////
        MALICIOUS / ADVERSARIAL HELPERS
//////////////////////////////////////////////////////////////*/

/// @notice A buyer contract that, on receiving GMB, tries to re-enter dispense for a SECOND
/// payout (double-spend). It swallows the re-entry revert so we can prove it still only ever
/// receives ONCE — i.e. reentrancy cannot double-spend.
contract ReentrantBuyer {
    GembaPayDispenser public immutable d;
    uint256 public received;
    constructor(GembaPayDispenser _d) { d = _d; }
    receive() external payable {
        received += msg.value;
        try d.dispense(payable(address(this)), msg.value, bytes32(0)) {} catch {}
        try d.withdraw(payable(address(this)), msg.value) {} catch {}
    }
}

/// @notice Tries to push native GMB into the dispenser directly (must be rejected).
contract DirectPusher {
    function push(address payable target) external payable returns (bool ok) {
        (ok, ) = target.call{value: msg.value}("");
    }
}

/*//////////////////////////////////////////////////////////////
                            TESTS
//////////////////////////////////////////////////////////////*/

contract GembaPayDispenserTest is Test {
    GembaPayDispenser disp;

    address owner = makeAddr("owner");
    address buyer = makeAddr("buyer");
    address attacker = makeAddr("attacker");

    bytes32 constant REF = keccak256("order-123");

    function setUp() public {
        vm.prank(owner);
        disp = new GembaPayDispenser(owner);
        // fund with 100 GMB via the owner-only fund()
        vm.deal(owner, 1_000 ether);
        vm.prank(owner);
        disp.fund{value: 100 ether}();
    }

    /*----------------------------- HAPPY PATH -----------------------------*/

    function test_Fund_creditsReserve() public {
        assertEq(disp.balance(), 100 ether);
        vm.prank(owner);
        disp.fund{value: 50 ether}();
        assertEq(disp.balance(), 150 ether);
    }

    function test_Dispense_paysBuyer() public {
        uint256 before = buyer.balance;
        vm.prank(owner);
        disp.dispense(payable(buyer), 10 ether, REF);
        assertEq(buyer.balance - before, 10 ether, "buyer not paid");
        assertEq(disp.balance(), 90 ether, "reserve not debited");
    }

    function test_Withdraw_returnsToOwner() public {
        uint256 before = owner.balance;
        vm.prank(owner);
        disp.withdraw(payable(owner), 40 ether);
        assertEq(owner.balance - before, 40 ether);
        assertEq(disp.balance(), 60 ether);
    }

    /*----------------------------- ACCESS CONTROL -----------------------------*/

    function test_OnlyOwner_fund() public {
        vm.deal(attacker, 10 ether);
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        disp.fund{value: 1 ether}();
    }

    function test_OnlyOwner_dispense() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        disp.dispense(payable(attacker), 1 ether, REF);
    }

    function test_OnlyOwner_withdraw() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        disp.withdraw(payable(attacker), 1 ether);
    }

    function test_OnlyOwner_pause() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
        disp.pause();
    }

    /*----------------------------- REJECTS WHAT IT SHOULD NOT HOLD -----------------------------*/

    function test_DirectNativeSend_reverts() public {
        DirectPusher p = new DirectPusher();
        vm.deal(address(p), 5 ether);
        // low-level push returns false because receive() reverts; reserve unchanged
        bool ok = p.push{value: 5 ether}(payable(address(disp)));
        assertFalse(ok, "direct deposit should be rejected");
        assertEq(disp.balance(), 100 ether, "reserve must not change");
    }

    function test_PlainTransfer_reverts() public {
        vm.deal(address(this), 1 ether);
        (bool ok, ) = address(disp).call{value: 1 ether}("");
        assertFalse(ok, "receive() must reject");
    }

    function test_Rejects_ERC721() public {
        vm.expectRevert(GembaPayDispenser.TokensNotAccepted.selector);
        disp.onERC721Received(address(0), address(0), 1, "");
    }

    function test_Rejects_ERC1155() public {
        vm.expectRevert(GembaPayDispenser.TokensNotAccepted.selector);
        disp.onERC1155Received(address(0), address(0), 1, 1, "");
        uint256[] memory a = new uint256[](0);
        vm.expectRevert(GembaPayDispenser.TokensNotAccepted.selector);
        disp.onERC1155BatchReceived(address(0), address(0), a, a, "");
    }

    /*----------------------------- REENTRANCY (the core proof) -----------------------------*/

    /// A malicious buyer that re-enters dispense+withdraw on receive() cannot double-spend:
    /// it receives EXACTLY once, the reserve drops by exactly that one payout, the re-entries
    /// fail (not owner / nonReentrant).
    function test_Reentrancy_cannotDoubleSpend() public {
        ReentrantBuyer evil = new ReentrantBuyer(disp);
        vm.prank(owner);
        disp.dispense(payable(address(evil)), 10 ether, REF);
        assertEq(evil.received(), 10 ether, "buyer must receive exactly one payout");
        assertEq(disp.balance(), 90 ether, "reserve drained beyond one payout!");
    }

    /*----------------------------- BOUNDS / VALIDATION -----------------------------*/

    function test_Dispense_insufficientBalance_reverts() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(GembaPayDispenser.InsufficientBalance.selector, 100 ether, 101 ether));
        disp.dispense(payable(buyer), 101 ether, REF);
    }

    function test_Dispense_zeroAddress_reverts() public {
        vm.prank(owner);
        vm.expectRevert(GembaPayDispenser.ZeroAddress.selector);
        disp.dispense(payable(address(0)), 1 ether, REF);
    }

    function test_Dispense_zeroAmount_reverts() public {
        vm.prank(owner);
        vm.expectRevert(GembaPayDispenser.ZeroAmount.selector);
        disp.dispense(payable(buyer), 0, REF);
    }

    function test_Fund_zeroAmount_reverts() public {
        vm.prank(owner);
        vm.expectRevert(GembaPayDispenser.ZeroAmount.selector);
        disp.fund{value: 0}();
    }

    /*----------------------------- PAUSE -----------------------------*/

    function test_Pause_blocksDispense_butAllowsWithdraw() public {
        vm.prank(owner);
        disp.pause();
        vm.prank(owner);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        disp.dispense(payable(buyer), 1 ether, REF);
        // withdraw is allowed while paused (incident recovery)
        vm.prank(owner);
        disp.withdraw(payable(owner), 1 ether);
        assertEq(disp.dispensable(), 0, "dispensable must be 0 while paused");
        // unpause restores dispensing
        vm.prank(owner);
        disp.unpause();
        vm.prank(owner);
        disp.dispense(payable(buyer), 1 ether, REF);
        assertEq(buyer.balance, 1 ether);
    }

    /*----------------------------- OWNERSHIP -----------------------------*/

    function test_Ownable2Step() public {
        vm.prank(owner);
        disp.transferOwnership(buyer);
        assertEq(disp.owner(), owner, "must not transfer until accepted");
        vm.prank(buyer);
        disp.acceptOwnership();
        assertEq(disp.owner(), buyer);
    }

    /*----------------------------- FUZZ -----------------------------*/

    function testFuzz_DispenseNeverExceedsReserve(uint96 amt) public {
        uint256 bal = disp.balance();
        vm.prank(owner);
        if (amt == 0) {
            vm.expectRevert(GembaPayDispenser.ZeroAmount.selector);
            disp.dispense(payable(buyer), amt, REF);
        } else if (amt > bal) {
            vm.expectRevert(abi.encodeWithSelector(GembaPayDispenser.InsufficientBalance.selector, bal, amt));
            disp.dispense(payable(buyer), amt, REF);
        } else {
            disp.dispense(payable(buyer), amt, REF);
            assertEq(disp.balance(), bal - amt);
            assertEq(buyer.balance, amt);
        }
    }
}
