// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IGembaTicketing {
    function issue(address to, uint256 eventId, uint256 amount) external;
}

/// @title GembaPerks
/// @notice Employee-bonus / perks flow (CLAUDE.md §2: workplace perks). An
/// institution funds this contract with GMB; an appointed distributor (HR/ops)
/// pays GMB **bonuses** to employees and grants **perk tickets** (via the
/// GembaTicketing contract). Follows docs/security-standards.md: `nonReentrant` on
/// every value/external-call path, events on every state change, custom errors,
/// per-bonus cap, fail loud.
contract GembaPerks is AccessControl, ReentrancyGuard {
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice the ticketing contract used to grant perk tickets. This contract
    /// must hold ORGANIZER_ROLE on it (granted by the ticketing admin).
    IGembaTicketing public immutable ticketing;

    /// @notice maximum GMB a single bonus payment may disburse (admin-set cap).
    uint256 public maxBonus;

    event BonusPaid(address indexed employee, uint256 amount, address indexed by);
    event BonusFailed(address indexed employee, uint256 amount, address indexed by);
    event PerkGranted(address indexed employee, uint256 indexed eventId, address indexed by);
    event MaxBonusSet(uint256 maxBonus);
    event Funded(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error AboveMaxBonus();
    error InsufficientBalance();
    error NativeSendFailed();
    error LengthMismatch();

    constructor(address admin, IGembaTicketing ticketing_, uint256 maxBonus_) {
        if (admin == address(0) || address(ticketing_) == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        ticketing = ticketing_;
        maxBonus = maxBonus_;
    }

    /// @notice Pay one employee a GMB bonus (≤ maxBonus). Distributor only.
    function payBonus(address employee, uint256 amount) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        _payBonus(employee, amount);
    }

    /// @notice Pay several employees in one call.
    function payBonusBatch(address[] calldata employees, uint256[] calldata amounts)
        external
        onlyRole(DISTRIBUTOR_ROLE)
        nonReentrant
    {
        if (employees.length != amounts.length) revert LengthMismatch();
        // Isolate per-recipient failures: a single reverting recipient must NOT block bonuses
        // for everyone else in the batch (audit finding #8). Failures emit BonusFailed; the
        // distributor re-runs the failed ones (or uses single payBonus).
        for (uint256 i = 0; i < employees.length; i++) {
            _tryPayBonus(employees[i], amounts[i]);
        }
    }

    function _payBonus(address employee, uint256 amount) internal {
        if (employee == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > maxBonus) revert AboveMaxBonus();
        if (address(this).balance < amount) revert InsufficientBalance();
        (bool ok, ) = payable(employee).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
        emit BonusPaid(employee, amount, msg.sender);
    }

    /// @dev Batch-safe variant: validates + pays, but on ANY failure emits BonusFailed and
    /// returns false instead of reverting, so one bad recipient can't DoS the whole batch
    /// (audit finding #8). Re-reads balance each call (decreases as payouts succeed). The
    /// caller (payBonusBatch) is nonReentrant, so a reverting recipient cannot reenter.
    function _tryPayBonus(address employee, uint256 amount) internal returns (bool) {
        if (employee == address(0) || amount == 0 || amount > maxBonus || address(this).balance < amount) {
            emit BonusFailed(employee, amount, msg.sender);
            return false;
        }
        (bool ok, ) = payable(employee).call{value: amount}("");
        if (!ok) {
            emit BonusFailed(employee, amount, msg.sender);
            return false;
        }
        emit BonusPaid(employee, amount, msg.sender);
        return true;
    }

    /// @notice Grant an employee a perk ticket for `eventId`. Distributor only.
    function grantPerk(address employee, uint256 eventId) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        if (employee == address(0)) revert ZeroAddress();
        ticketing.issue(employee, eventId, 1); // external call (mints the ticket)
        emit PerkGranted(employee, eventId, msg.sender);
    }

    // --- admin ---

    function setMaxBonus(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxBonus = newMax;
        emit MaxBonusSet(newMax);
    }

    function withdraw(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientBalance();
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
        emit Withdrawn(to, amount);
    }

    /// @notice Institution funds the perks pool with native GMB.
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
