// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {BaseReserve} from "./BaseReserve.sol";

/// @title ContingencyReserve
/// @notice Holds the 10% contingency bucket (CLAUDE.md §4.1, §8) — *резерв за
/// непредвидени нужди*. Reserved for unforeseen/strategic needs. Replaces the former
/// liquidity reserve: GembaBlockchain seeds **no** liquidity and runs no exchange by
/// design (§2, §16.1). Released only by the owner (Timelock) + delay. Non-voting.
/// Upgradeable; upgrade authority = Timelock only.
contract ContingencyReserve is BaseReserve {
    function initialize(address owner_, address pauser_) external initializer {
        __BaseReserve_init(owner_, pauser_);
    }
}
