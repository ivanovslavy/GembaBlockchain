// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title GembaPayDispenser
 * @author GEMBA IT
 * @notice A secure, payment-agnostic GMB vault for GembaPay. It holds native GMB and lets
 *         **only the owner** (the GembaPay backend signer) send GMB out — to a buyer after a
 *         payment is settled off-chain (fiat OR crypto, GembaPay decides), or back to the owner.
 *
 * @dev Design (secure by default, fail loud — CLAUDE.md §11):
 *      - **Owner is the only mover of funds.** `dispense` (to a buyer) and `withdraw` (recovery)
 *        are `onlyOwner`. No one else can move a wei.
 *      - **Ownable2Step** — ownership can never be handed to a wrong/dead address by a typo.
 *      - **Pausable** — the owner can freeze dispensing during an incident.
 *      - **ReentrancyGuard** on every value-moving function (defence-in-depth; the contract holds
 *        no per-user state to corrupt, and only the owner can call, so reentrancy is already
 *        impossible — the guard is a belt on top of the braces).
 *      - **Rejects everything it should not hold:** no anonymous native deposits (`receive`/
 *        `fallback` revert), and ERC-721/1155 safe-transfers revert (the receiver hooks revert).
 *        Funding is **only** via the explicit owner-only `fund()`.
 *      - Native sends via OpenZeppelin `Address.sendValue`; custom errors; an event on every
 *        state-changing call; ample read functions.
 *
 *      ERC-20 note: no contract can stop a *raw* `ERC20.transfer` push (it never calls the
 *      recipient), but this contract has **no ERC-20 logic** — any pushed ERC-20 is inert and
 *      simply ignored. There is deliberately no token-handling surface.
 */
contract GembaPayDispenser is Ownable2Step, Pausable, ReentrancyGuard {
    string public constant VERSION = "1.0.0";

    event Funded(address indexed from, uint256 amount);
    event Dispensed(address indexed to, uint256 amount, bytes32 indexed ref);
    event Withdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 available, uint256 requested);
    error DirectDepositNotAllowed();
    error TokensNotAccepted();

    /// @param owner_ the GembaPay backend signer that will fund + dispense.
    constructor(address owner_) Ownable(owner_) {
        if (owner_ == address(0)) revert ZeroAddress();
    }

    // ============================================================
    //  FUNDING (owner only, explicit — no anonymous deposits)
    // ============================================================

    /// @notice Fund the dispenser's GMB reserve. Owner-only, explicit; bare sends are rejected.
    function fund() external payable onlyOwner {
        if (msg.value == 0) revert ZeroAmount();
        emit Funded(msg.sender, msg.value);
    }

    // ============================================================
    //  MOVING FUNDS OUT (owner only)
    // ============================================================

    /// @notice Send GMB to a buyer after GembaPay has settled the payment off-chain.
    /// @param to     buyer wallet.
    /// @param amount GMB to send (wei).
    /// @param ref    opaque off-chain payment reference (order/intent id) for on-chain audit.
    function dispense(address payable to, uint256 amount, bytes32 ref)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = address(this).balance;
        if (bal < amount) revert InsufficientBalance(bal, amount);
        Address.sendValue(to, amount);
        emit Dispensed(to, amount, ref);
    }

    /// @notice Owner recovers GMB from the dispenser (e.g. to refill, rotate, or wind down).
    function withdraw(address payable to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = address(this).balance;
        if (bal < amount) revert InsufficientBalance(bal, amount);
        Address.sendValue(to, amount);
        emit Withdrawn(to, amount);
    }

    // ============================================================
    //  PAUSE (owner only)
    // ============================================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ============================================================
    //  VIEWS
    // ============================================================

    /// @notice Current GMB held by the dispenser (wei).
    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice GMB available to dispense right now (0 while paused).
    function dispensable() external view returns (uint256) {
        return paused() ? 0 : address(this).balance;
    }

    // ============================================================
    //  REJECT EVERYTHING IT SHOULD NOT HOLD
    // ============================================================

    /// @dev No anonymous native deposits — funding is only via owner-only `fund()`.
    receive() external payable {
        revert DirectDepositNotAllowed();
    }

    fallback() external payable {
        revert DirectDepositNotAllowed();
    }

    /// @dev Explicitly reject ERC-721 safe transfers (no NFT custody).
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        revert TokensNotAccepted();
    }

    /// @dev Explicitly reject ERC-1155 safe transfers (single + batch).
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
        revert TokensNotAccepted();
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        revert TokensNotAccepted();
    }
}
