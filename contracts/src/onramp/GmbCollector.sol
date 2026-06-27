// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title GmbCollector
 * @author GEMBA IT
 * @notice Minimal **native-GMB** payment collector for GembaPay. A customer pays GMB for an order
 *         via `pay(orderId)`; the GMB is forwarded immediately to `recipient`. Modelled on
 *         GembaPayEuro but stripped to one job and native-only (no ERC-20 / oracle / fee).
 *
 * @dev Single responsibility: **an orderId can be paid only ONCE** (no double payment) — that is
 *      the whole point of having a contract instead of a plain transfer (it binds the payment to an
 *      orderId in an event the GembaPay listener can consume). 1 GMB = 1 EUR by design, no oracle.
 *      Native only: it rejects direct GMB sends, ERC-20, ERC-721 and ERC-1155.
 *      Secure by default: Ownable2Step + Pausable + ReentrancyGuard, strict CEI (the order is
 *      marked paid BEFORE the forward), custom errors, an event on every state change.
 *      Emits the same `PaymentProcessed` shape as GembaPayEuro so the existing event-listener
 *      consumes it by only adding the GembaBlockchain network (no listener logic change).
 */
contract GmbCollector is Ownable2Step, Pausable, ReentrancyGuard {
    string public constant VERSION = "1.0.0";

    /// @notice Where collected GMB is forwarded. Changeable by the owner.
    address payable public recipient;
    /// @notice Incrementing id assigned to each successful payment.
    uint256 public paymentCount;
    /// @notice keccak256(orderId) => already paid. The double-payment guard.
    mapping(bytes32 => bool) public paidOrders;

    event PaymentProcessed(
        uint256 indexed paymentId,
        address indexed merchant,
        address indexed customer,
        address token,
        uint256 totalAmount,
        uint256 merchantAmount,
        uint256 feeAmount,
        uint256 eurCents,
        string orderId,
        uint256 blockNumber
    );
    event RecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

    error ZeroAddress();
    error ZeroAmount();
    error EmptyOrderId();
    error OrderAlreadyPaid();
    error DirectPaymentNotAllowed();
    error TokensNotAccepted();

    /// @param owner_ contract owner (config). @param recipient_ initial GMB recipient.
    constructor(address owner_, address payable recipient_) Ownable(owner_) {
        if (owner_ == address(0) || recipient_ == address(0)) revert ZeroAddress();
        recipient = recipient_;
        emit RecipientUpdated(address(0), recipient_);
    }

    /**
     * @notice Pay GMB for `orderId`. The GMB is forwarded to `recipient`. Reverts `OrderAlreadyPaid`
     *         if this orderId was already paid (the single job: no duplicate payment).
     * @param orderId the GembaPay order identifier this payment settles.
     */
    function pay(string calldata orderId) external payable whenNotPaused nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        if (bytes(orderId).length == 0) revert EmptyOrderId();
        bytes32 h = keccak256(bytes(orderId));
        if (paidOrders[h]) revert OrderAlreadyPaid();
        paidOrders[h] = true; // effect before interaction (CEI) — blocks reentrant double-pay too
        uint256 amount = msg.value;
        uint256 id = ++paymentCount;
        address payable to = recipient;
        Address.sendValue(to, amount);
        // 1 GMB (1e18 wei) = €1 = 100 cents → eurCents = amount / 1e16
        emit PaymentProcessed(id, to, msg.sender, address(0), amount, amount, 0, amount / 1e16, orderId, block.number);
    }

    /// @notice True if `orderId` has already been paid.
    function isOrderPaid(string calldata orderId) external view returns (bool) {
        return paidOrders[keccak256(bytes(orderId))];
    }

    /// @notice Owner changes the GMB recipient address.
    function setRecipient(address payable newRecipient) external onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        emit RecipientUpdated(recipient, newRecipient);
        recipient = newRecipient;
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // ----- reject everything that is not a pay() call -----
    receive() external payable { revert DirectPaymentNotAllowed(); }
    fallback() external payable { revert DirectPaymentNotAllowed(); }
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) { revert TokensNotAccepted(); }
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) { revert TokensNotAccepted(); }
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external pure returns (bytes4) { revert TokensNotAccepted(); }
}
