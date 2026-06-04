// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title GembaTimelock
/// @notice The execution layer for treasury/contract governance (CLAUDE.md §7).
/// Proposals approved by the Governor are queued here and can only execute after
/// the delay; then ANYONE may execute (no privileged signer keeps the system
/// running). The Timelock is the owner/upgrade authority of every reserve
/// contract, so funds and upgrades move only via propose → vote → delay → execute.
///
/// Roles (set at deployment): PROPOSER = the Governor; EXECUTOR = address(0)
/// (open execution); the deployer renounces admin so no EOA retains control.
contract GembaTimelock is TimelockController {
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
