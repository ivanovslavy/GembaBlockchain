// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {BaseReserve} from "./BaseReserve.sol";

/// @title DAOReserve
/// @notice Holds the 10% DAO contingency bucket (CLAUDE.md §4.1): unforeseen needs,
/// released by governance. Funds leave only via the owner (Timelock). Non-voting.
/// Upgradeable; upgrade authority = Timelock only.
contract DAOReserve is BaseReserve {
    function initialize(address owner_, address pauser_) external initializer {
        __BaseReserve_init(owner_, pauser_);
    }
}
