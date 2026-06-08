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

    // --- rolling window cap (defence in depth: a single per-call cap does NOT bound a
    // compromised granter who calls grant() repeatedly; this caps the *aggregate* flow per
    // time window). NOTE (audit L-1): this bounds the RATE, not the lifetime total — a
    // granter key compromised and left undetected could still slow-drain at epochCap/window.
    // It is NOT drain-proof; the real responses to a stolen granter are setGranter (owner,
    // instant revoke), EmergencyPause (2-of-3, halt all grants), and setEpochLimit. Accepted
    // trade-off per CLAUDE.md §16.5. epochCap == 0 disables the window cap. ---
    /// @notice max cumulative GMB grantable within one rolling window (0 = no window cap).
    uint256 public epochCap;
    /// @notice rolling window length in seconds.
    uint256 public epochLength;
    /// @notice timestamp the current window started.
    uint256 public epochStart;
    /// @notice GMB granted so far in the current window.
    uint256 public epochSpent;

    event Granted(address indexed to, uint256 amount);
    event GranterUpdated(address indexed previous, address indexed current);
    event PerGrantCapUpdated(uint256 previous, uint256 current);
    event EpochLimitUpdated(uint256 cap, uint256 length);

    error OnlyGranter();
    error AboveCap();
    error AboveEpochCap();
    error InvalidEpochConfig();

    /// @param owner_ Timelock. @param pauser_ EmergencyPause. @param granter_ formula actor.
    /// @param perGrantCap_ max per capped grant. @param epochCap_ max per rolling window
    /// (0 = disabled). @param epochLength_ window length in seconds.
    function initialize(
        address owner_,
        address pauser_,
        address granter_,
        uint256 perGrantCap_,
        uint256 epochCap_,
        uint256 epochLength_
    ) external initializer {
        // a non-zero cap with a zero window would reset every call and silently void the cap
        if (epochCap_ != 0 && epochLength_ == 0) revert InvalidEpochConfig(); // audit finding #6
        __BaseReserve_init(owner_, pauser_);
        granter = granter_;
        perGrantCap = perGrantCap_;
        epochCap = epochCap_;
        epochLength = epochLength_;
        epochStart = block.timestamp;
    }

    /// @notice Rate-limited grant by the formula actor (or governance). Capped per
    /// call AND per rolling window; blocked while paused. Above either cap, governance
    /// uses `release` (owner/Timelock, uncapped) or raises the limits.
    function grant(address payable to, uint256 amount) external whenNotPaused nonReentrant {
        if (msg.sender != granter && msg.sender != owner()) revert OnlyGranter();
        if (amount > perGrantCap) revert AboveCap();
        // rolling-window aggregate cap (effects-before-interaction: state updated first)
        if (epochCap != 0) {
            if (block.timestamp >= epochStart + epochLength) {
                epochStart = block.timestamp;
                epochSpent = 0;
            }
            if (epochSpent + amount > epochCap) revert AboveEpochCap();
            epochSpent += amount;
        }
        totalGranted += amount;
        _release(to, amount);
        emit Granted(to, amount);
    }

    /// @notice Governance tunes the rolling-window aggregate cap (the real drain bound).
    function setEpochLimit(uint256 newCap, uint256 newLength) external onlyOwner {
        if (newCap != 0 && newLength == 0) revert InvalidEpochConfig(); // audit finding #6
        epochCap = newCap;
        epochLength = newLength;
        epochStart = block.timestamp;
        epochSpent = 0;
        emit EpochLimitUpdated(newCap, newLength);
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
