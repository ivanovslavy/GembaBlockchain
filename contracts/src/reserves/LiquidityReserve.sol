// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {BaseReserve} from "./BaseReserve.sol";

/// @title LiquidityReserve
/// @notice Holds the 10% liquidity bucket (CLAUDE.md §4.1, §8): seeds/deepens
/// liquidity if/when governance decides — supports depth, not price control.
/// Released only by the owner (Timelock) + delay. Non-voting. Upgradeable; upgrade
/// authority = Timelock only.
contract LiquidityReserve is BaseReserve {
    function initialize(address owner_, address pauser_) external initializer {
        __BaseReserve_init(owner_, pauser_);
    }
}
