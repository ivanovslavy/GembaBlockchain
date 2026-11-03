// SPDX-License-Identifier: GPL-3.0-or-later
//
// Derived from Uniswap V2: contracts/interfaces/IUniswapV2ERC20.sol in https://github.com/Uniswap/v2-core
// Original work Copyright (C) 2020 Uniswap Labs (formerly Uniswap) and the Uniswap V2 authors,
// licensed under the GNU General Public License, version 3 or (at your option) any later version.
// Modified 2026 by GEMBA EOOD for GembaBlockchain:
//   - identifiers renamed UniswapV2* -> GembaSwap* (contracts, interfaces, libraries, revert-string prefixes)
// This file is distributed under GPL-3.0-or-later, NOT the Apache-2.0 licence of the rest of the
// repository. See LICENSE and NOTICE in contracts/src/dex/gembaswap/.
pragma solidity >=0.5.0;

interface IGembaSwapERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}
