// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";

/// @title WorkplaceCheckIn
/// @notice Demo target for sponsored gas (Phase 4) and a preview of the access-
/// control use case (Phase 5). An employee "checks in"; because this contract is
/// ERC2771Context-aware, `_msgSender()` resolves to the EMPLOYEE even when the
/// transaction was submitted (and gas-paid) by the institution's relayer through
/// the GembaForwarder. So the action is attributed to the employee, who holds no
/// GMB and signed only off-chain. No PII is stored on-chain (CLAUDE.md §10).
contract WorkplaceCheckIn is ERC2771Context {
    mapping(address => uint256) public checkIns;
    address public lastCheckedIn;

    event CheckedIn(address indexed employee, uint256 count);

    constructor(address trustedForwarder_) ERC2771Context(trustedForwarder_) {}

    /// @notice Record a check-in for the real caller (the employee, via EIP-2771).
    function checkIn() external {
        address employee = _msgSender();
        uint256 count = checkIns[employee] + 1;
        checkIns[employee] = count;
        lastCheckedIn = employee;
        emit CheckedIn(employee, count);
    }
}
