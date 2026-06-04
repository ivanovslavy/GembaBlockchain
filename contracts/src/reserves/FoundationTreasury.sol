// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {BaseReserve} from "./BaseReserve.sol";

/// @title FoundationTreasury
/// @notice Holds the 15% foundation bucket (CLAUDE.md §4.1): dev funding, audits.
/// Funds are released only by the owner (Timelock) via governance + delay. Non-
/// voting (excluded in GembaVotes). Upgradeable; upgrade authority = Timelock only.
contract FoundationTreasury is BaseReserve {
    /// @param owner_ the Timelock (governance). @param pauser_ the EmergencyPause guardian.
    function initialize(address owner_, address pauser_) external initializer {
        __BaseReserve_init(owner_, pauser_);
    }
}
