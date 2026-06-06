// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {GembaSwapPair} from "./GembaSwapPair.sol";

/// @title GembaSwapFactory
/// @notice Permissionless factory that deploys one constant-product pair per ERC-20
/// pair, Uniswap-V2-style. Anyone can create a pair. Third-party developer
/// infrastructure (see WGMB.sol for the positioning note) — not operated by the
/// project, not for GMB.
contract GembaSwapFactory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256 index);

    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();

    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Create the pool for (tokenA, tokenB). Reverts if it already exists.
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
        if (getPair[token0][token1] != address(0)) revert PairExists();

        GembaSwapPair p = new GembaSwapPair();
        p.initialize(token0, token1);
        pair = address(p);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length - 1);
    }
}
