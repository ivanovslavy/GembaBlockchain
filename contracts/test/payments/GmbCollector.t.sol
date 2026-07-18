// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GmbCollector} from "../../src/payments/GmbCollector.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// Recipient that re-enters pay() on receive() (swallowing the revert) — proves reentrancy
/// cannot create a second payment / double-spend.
contract ReentrantRecipient {
    GmbCollector public c;
    uint256 public got;
    function set(GmbCollector _c) external { c = _c; }
    receive() external payable {
        got += msg.value;
        try c.pay{value: 1 ether}("reentry") {} catch {}
    }
}

contract Pusher {
    function push(address payable t) external payable returns (bool ok) { (ok, ) = t.call{value: msg.value}(""); }
}

contract GmbCollectorTest is Test {
    GmbCollector col;
    address owner = makeAddr("owner");
    address recipient = makeAddr("recipient");
    address payer = makeAddr("payer");

    function setUp() public {
        vm.prank(owner);
        col = new GmbCollector(owner, payable(recipient));
        vm.deal(payer, 1000 ether);
    }

    function test_Pay_forwardsToRecipient() public {
        vm.prank(payer);
        col.pay{value: 10 ether}("ord-1");
        assertEq(recipient.balance, 10 ether, "recipient not paid");
        assertEq(col.paymentCount(), 1);
        assertTrue(col.isOrderPaid("ord-1"));
    }

    /// THE single job: an order can be paid only once.
    function test_DoublePay_reverts() public {
        vm.prank(payer);
        col.pay{value: 5 ether}("ord-x");
        vm.prank(payer);
        vm.expectRevert(GmbCollector.OrderAlreadyPaid.selector);
        col.pay{value: 5 ether}("ord-x");
        assertEq(recipient.balance, 5 ether, "double payment got through!");
        assertEq(col.paymentCount(), 1);
    }

    function test_Pay_zeroValue_reverts() public {
        vm.prank(payer);
        vm.expectRevert(GmbCollector.ZeroAmount.selector);
        col.pay{value: 0}("ord-z");
    }

    function test_Pay_emptyOrderId_reverts() public {
        vm.prank(payer);
        vm.expectRevert(GmbCollector.EmptyOrderId.selector);
        col.pay{value: 1 ether}("");
    }

    function test_DirectSend_reverts() public {
        Pusher p = new Pusher();
        vm.deal(address(p), 5 ether);
        bool ok = p.push{value: 5 ether}(payable(address(col)));
        assertFalse(ok, "direct GMB send should be rejected");
        assertEq(address(col).balance, 0);
    }

    function test_Rejects_NFTs() public {
        vm.expectRevert(GmbCollector.TokensNotAccepted.selector);
        col.onERC721Received(address(0), address(0), 1, "");
        uint256[] memory a = new uint256[](0);
        vm.expectRevert(GmbCollector.TokensNotAccepted.selector);
        col.onERC1155Received(address(0), address(0), 1, 1, "");
        vm.expectRevert(GmbCollector.TokensNotAccepted.selector);
        col.onERC1155BatchReceived(address(0), address(0), a, a, "");
    }

    function test_SetRecipient_ownerOnly_andWorks() public {
        address newR = makeAddr("newR");
        vm.prank(payer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, payer));
        col.setRecipient(payable(newR));
        vm.prank(owner);
        col.setRecipient(payable(newR));
        assertEq(col.recipient(), newR);
        vm.prank(payer);
        col.pay{value: 3 ether}("ord-new");
        assertEq(newR.balance, 3 ether);
    }

    function test_SetRecipient_zeroAddr_reverts() public {
        vm.prank(owner);
        vm.expectRevert(GmbCollector.ZeroAddress.selector);
        col.setRecipient(payable(address(0)));
    }

    function test_Pause_blocksPay() public {
        vm.prank(owner);
        col.pause();
        vm.prank(payer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        col.pay{value: 1 ether}("ord-p");
        vm.prank(owner);
        col.unpause();
        vm.prank(payer);
        col.pay{value: 1 ether}("ord-p");
        assertEq(recipient.balance, 1 ether);
    }

    /// A malicious recipient that re-enters pay() cannot double-spend or create a 2nd payment.
    function test_Reentrancy_cannotDouble() public {
        ReentrantRecipient evil = new ReentrantRecipient();
        evil.set(col);
        vm.deal(address(evil), 5 ether);
        vm.prank(owner);
        col.setRecipient(payable(address(evil)));
        vm.prank(payer);
        col.pay{value: 2 ether}("ord-re");
        assertEq(col.paymentCount(), 1, "reentrancy created a second payment!");
        assertEq(evil.got(), 2 ether, "recipient received exactly one payout");
    }

    function test_Ownable2Step() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        col.transferOwnership(newOwner);
        assertEq(col.owner(), owner, "must not transfer until accepted");
        vm.prank(newOwner);
        col.acceptOwnership();
        assertEq(col.owner(), newOwner);
    }

    function testFuzz_PayForwardsExact(uint96 amt) public {
        amt = uint96(bound(amt, 1, 900 ether));
        vm.prank(payer);
        col.pay{value: amt}("ord-fuzz");
        assertEq(recipient.balance, amt);
        assertTrue(col.isOrderPaid("ord-fuzz"));
    }
}
