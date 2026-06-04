// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {BaseReserve} from "./BaseReserve.sol";

/// @title Faucet
/// @notice The 30% public/municipal reserve (CLAUDE.md §4.1, §6). It receives the
/// 40% fee inflow from the `x/feesplit` Go module (the Cosmos↔EVM seam: feesplit
/// deposits native GMB straight into this contract's address — see
/// docs/phase3-treasury-principles.md), and grants GMB to institutions.
///
/// Two-tier exit, both governance-controlled:
///  - **Capped grants** (`grant`): a governance-appointed `granter` (the formula /
///    automation actor, §6 "small automatic grants by formula") may send up to
///    `perGrantCap` per call. This is the routine, rate-limited tap.
///  - **Large grants** (`release`, inherited): owner (Timelock) only, uncapped —
///    "a large grant requires governance + timelock" (§6).
///
/// You govern the *tap*, not water already poured (§6): control is the cap + the
/// granter appointment, both revocable by governance.
contract Faucet is BaseReserve {
    /// @notice formula/automation actor allowed to make capped grants (0 = none).
    address public granter;
    /// @notice maximum GMB a single `grant` call may disburse.
    uint256 public perGrantCap;
    /// @notice cumulative GMB granted via `grant` (telemetry / off-chain formulas).
    uint256 public totalGranted;

    event Granted(address indexed to, uint256 amount);
    event GranterUpdated(address indexed previous, address indexed current);
    event PerGrantCapUpdated(uint256 previous, uint256 current);

    error OnlyGranter();
    error AboveCap();

    /// @param owner_ Timelock. @param pauser_ EmergencyPause. @param granter_ formula actor.
    /// @param perGrantCap_ max per capped grant.
    function initialize(address owner_, address pauser_, address granter_, uint256 perGrantCap_) external initializer {
        __BaseReserve_init(owner_, pauser_);
        granter = granter_;
        perGrantCap = perGrantCap_;
    }

    /// @notice Rate-limited grant by the formula actor (or governance). Capped per
    /// call; blocked while paused. Above the cap, governance uses `release`.
    function grant(address payable to, uint256 amount) external whenNotPaused nonReentrant {
        if (msg.sender != granter && msg.sender != owner()) revert OnlyGranter();
        if (amount > perGrantCap) revert AboveCap();
        totalGranted += amount;
        _release(to, amount);
        emit Granted(to, amount);
    }

    /// @notice Governance appoints/revokes the formula actor.
    function setGranter(address newGranter) external onlyOwner {
        emit GranterUpdated(granter, newGranter);
        granter = newGranter;
    }

    /// @notice Governance tunes the per-grant cap (the "tap" rate, §6).
    function setPerGrantCap(uint256 newCap) external onlyOwner {
        emit PerGrantCapUpdated(perGrantCap, newCap);
        perGrantCap = newCap;
    }
}
