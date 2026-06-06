// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IPausableTarget {
    function pause() external;
    function unpause() external;
}

/// @title EmergencyPause
/// @notice The pause-only emergency guardian for the reserve contracts (CLAUDE.md
/// §7, docs/risks.md ADR-004). It is an m-of-n multisig of guardians that can ONLY
/// pause/unpause registered Pausable targets — it has no path to move or drain
/// funds (it only ever calls `pause()`/`unpause()`). This is bounded, revocable
/// power: the guardian set and threshold are managed by governance (the Timelock),
/// which can replace any guardian at any time.
contract EmergencyPause is ReentrancyGuard {
    enum Op {
        Pause,
        Unpause
    }

    /// @notice governance (Timelock) — manages guardians and the threshold.
    address public immutable governance;

    mapping(address => bool) public isGuardian;
    uint256 public guardianCount;
    /// @notice m-of-n threshold of guardian confirmations required to act.
    uint256 public threshold;
    /// @notice advances on every guardian/threshold change; mixed into the
    /// confirmation id so that ANY config change invalidates all pending
    /// confirmations. Prevents a removed guardian's stale confirmation from still
    /// counting toward a threshold (and the related front-running where a guardian
    /// pre-confirms just before being removed). No fund path either way — the
    /// contract can only pause/unpause — but votes must reflect the live set.
    uint256 public configEpoch;

    /// @dev current confirmation round per (target, op); advances on execution so
    /// the same action can be repeated later with fresh confirmations.
    mapping(address => mapping(uint8 => uint256)) public round;
    /// @dev confirmations counted per (target, op, round).
    mapping(bytes32 => uint256) public confirmations;
    mapping(bytes32 => mapping(address => bool)) public confirmedBy;

    event GuardianSet(address indexed guardian, bool enabled);
    event ThresholdSet(uint256 threshold);
    event ConfigEpochAdvanced(uint256 newEpoch);
    event Confirmed(address indexed guardian, address indexed target, Op op, uint256 round);
    event Executed(address indexed target, Op op, uint256 round);

    error OnlyGovernance();
    error OnlyGuardian();
    error AlreadyConfirmed();
    error BadThreshold();
    error ZeroAddress();

    constructor(address governance_, address[] memory guardians_, uint256 threshold_) {
        if (governance_ == address(0)) revert ZeroAddress();
        governance = governance_;
        for (uint256 i = 0; i < guardians_.length; i++) {
            address g = guardians_[i];
            if (g == address(0)) revert ZeroAddress();
            if (!isGuardian[g]) {
                isGuardian[g] = true;
                guardianCount++;
                emit GuardianSet(g, true);
            }
        }
        if (threshold_ == 0 || threshold_ > guardianCount) revert BadThreshold();
        threshold = threshold_;
        emit ThresholdSet(threshold_);
    }

    modifier onlyGovernance() {
        if (msg.sender != governance) revert OnlyGovernance();
        _;
    }

    /// @notice A guardian confirms pausing/unpausing `target`. When confirmations
    /// reach the threshold, the action executes and the round advances.
    /// @dev CEI: the round is advanced BEFORE the external `pause()/unpause()` call
    /// (no replay), and `nonReentrant` guards the external call. The id binds the
    /// current `configEpoch`, so any guardian/threshold change resets pending
    /// confirmations (no stale votes from a removed guardian).
    function confirm(address target, Op op) external nonReentrant {
        if (!isGuardian[msg.sender]) revert OnlyGuardian();
        if (target == address(0)) revert ZeroAddress();
        uint256 r = round[target][uint8(op)];
        bytes32 id = keccak256(abi.encode(target, op, r, configEpoch));
        if (confirmedBy[id][msg.sender]) revert AlreadyConfirmed();

        confirmedBy[id][msg.sender] = true;
        uint256 c = confirmations[id] + 1;
        confirmations[id] = c;
        emit Confirmed(msg.sender, target, op, r);

        if (c >= threshold) {
            round[target][uint8(op)] = r + 1; // next round before external call (no replay)
            emit Executed(target, op, r);
            if (op == Op.Pause) {
                IPausableTarget(target).pause();
            } else {
                IPausableTarget(target).unpause();
            }
        }
    }

    // --- governance management (bounded, revocable power) ---

    /// @notice Governance adds/removes a guardian. Replaceable at any time.
    function setGuardian(address guardian, bool enabled) external onlyGovernance {
        if (guardian == address(0)) revert ZeroAddress();
        if (isGuardian[guardian] == enabled) return;
        isGuardian[guardian] = enabled;
        if (enabled) {
            guardianCount++;
        } else {
            guardianCount--;
            if (threshold > guardianCount) revert BadThreshold(); // keep threshold satisfiable
        }
        emit GuardianSet(guardian, enabled);
        configEpoch++; // invalidate pending confirmations gathered under the old set
        emit ConfigEpochAdvanced(configEpoch);
    }

    /// @notice Governance sets the m-of-n threshold.
    function setThreshold(uint256 newThreshold) external onlyGovernance {
        if (newThreshold == 0 || newThreshold > guardianCount) revert BadThreshold();
        threshold = newThreshold;
        emit ThresholdSet(newThreshold);
        configEpoch++; // invalidate pending confirmations gathered under the old threshold
        emit ConfigEpochAdvanced(configEpoch);
    }
}
