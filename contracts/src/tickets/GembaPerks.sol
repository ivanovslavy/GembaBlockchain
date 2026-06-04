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
        for (uint256 i = 0; i < employees.length; i++) {
            _payBonus(employees[i], amounts[i]);
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
