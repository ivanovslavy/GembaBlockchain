// SPDX-License-Identifier: GPL-3.0-or-later
//
// Derived from Uniswap V2: contracts/interfaces/IERC20.sol in https://github.com/Uniswap/v2-periphery
// Original work Copyright (C) 2020 Uniswap Labs (formerly Uniswap) and the Uniswap V2 authors,
// licensed under the GNU General Public License, version 3 or (at your option) any later version.
// Modified 2026 by GEMBA EOOD for GembaBlockchain:
//   - no code changes; only this header was added
// This file is distributed under GPL-3.0-or-later, NOT the Apache-2.0 licence of the rest of the
// repository. See LICENSE and NOTICE in contracts/src/dex/gembaswap/.
pragma solidity >=0.5.0;

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}
