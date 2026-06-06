// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LiquidityLocker
/// @notice Time-locks ERC-20 tokens (typically GembaSwap LP tokens) until a chosen
/// timestamp, so a developer can prove their liquidity is locked (anti-rug). The
/// lock owner can only WITHDRAW after `unlockTime`, and can only EXTEND (never
/// shorten) a lock. The contract has no admin and no path to move locked tokens —
/// not even by the deployer. Third-party developer infrastructure (see WGMB.sol).
/// Follows docs/security-standards.md: CEI + `nonReentrant`, SafeERC20, events on
/// every state change, custom errors, fail loud.
contract LiquidityLocker is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Lock {
        address owner;
        address token;
        uint256 amount;
        uint64 unlockTime;
        bool withdrawn;
    }

    mapping(uint256 => Lock) public locks;
    uint256 public nextLockId;
    mapping(address => uint256[]) private _userLockIds;

    event Locked(
        uint256 indexed lockId, address indexed owner, address indexed token, uint256 amount, uint64 unlockTime
    );
    event Withdrawn(uint256 indexed lockId, address indexed owner, uint256 amount);
    event Extended(uint256 indexed lockId, uint64 oldUnlockTime, uint64 newUnlockTime);

    error ZeroAddress();
    error ZeroAmount();
    error UnlockInPast();
    error NotLockOwner();
    error AlreadyWithdrawn();
    error StillLocked();
    error CannotShorten();

    /// @notice Lock `amount` of `token` until `unlockTime`. Records the amount
    /// actually received (fee-on-transfer safe). Returns the new lock id.
    function lock(address token, uint256 amount, uint64 unlockTime)
        external
        nonReentrant
        returns (uint256 lockId)
    {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (unlockTime <= block.timestamp) revert UnlockInPast();

        uint256 balBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;
        if (received == 0) revert ZeroAmount();

        lockId = nextLockId++;
        locks[lockId] =
            Lock({owner: msg.sender, token: token, amount: received, unlockTime: unlockTime, withdrawn: false});
        _userLockIds[msg.sender].push(lockId);
        emit Locked(lockId, msg.sender, token, received, unlockTime);
    }

    /// @notice Withdraw a matured lock to its owner.
    function withdraw(uint256 lockId) external nonReentrant {
        Lock storage l = locks[lockId];
        if (l.owner != msg.sender) revert NotLockOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        if (block.timestamp < l.unlockTime) revert StillLocked();

        l.withdrawn = true; // effect before interaction
        uint256 amount = l.amount;
        IERC20(l.token).safeTransfer(l.owner, amount);
        emit Withdrawn(lockId, l.owner, amount);
    }

    /// @notice Extend a lock's unlock time (can only push it later).
    function extend(uint256 lockId, uint64 newUnlockTime) external {
        Lock storage l = locks[lockId];
        if (l.owner != msg.sender) revert NotLockOwner();
        if (l.withdrawn) revert AlreadyWithdrawn();
        if (newUnlockTime <= l.unlockTime) revert CannotShorten();
        uint64 old = l.unlockTime;
        l.unlockTime = newUnlockTime;
        emit Extended(lockId, old, newUnlockTime);
    }

    // --- views ---

    function getLock(uint256 lockId) external view returns (Lock memory) {
        return locks[lockId];
    }

    function userLockIds(address user) external view returns (uint256[] memory) {
        return _userLockIds[user];
    }

    function lockCountOf(address user) external view returns (uint256) {
        return _userLockIds[user].length;
    }
}
