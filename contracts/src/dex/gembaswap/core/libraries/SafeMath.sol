// SPDX-License-Identifier: GPL-3.0-or-later
//
// Derived from Uniswap V2: contracts/libraries/SafeMath.sol in https://github.com/Uniswap/v2-core
// Original work Copyright (C) 2020 Uniswap Labs (formerly Uniswap) and the Uniswap V2 authors,
// licensed under the GNU General Public License, version 3 or (at your option) any later version.
// Modified 2026 by GEMBA EOOD for GembaBlockchain:
//   - no code changes; only this header was added
// This file is distributed under GPL-3.0-or-later, NOT the Apache-2.0 licence of the rest of the
// repository. See LICENSE and NOTICE in contracts/src/dex/gembaswap/.
pragma solidity =0.5.16;

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
}
