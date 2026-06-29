// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

/// @notice Minimal reentrancy guard (no external deps) — used on every value-moving path
/// per docs/security-standards.md (CEI + nonReentrant). Self-contained so the endurance
/// Foundry project needs no OZ install for its `src` artifacts.
abstract contract ReentrancyGuard {
    uint256 private _status; // 0/1 = not entered, 2 = entered
    error Reentrancy();

    modifier nonReentrant() {
        if (_status == 2) revert Reentrancy();
        _status = 2;
        _;
        _status = 1;
    }
}
