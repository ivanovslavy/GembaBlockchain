// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {GembaNativePool} from "./GembaNativePool.sol";

/// @title GembaNativePoolFactory
/// @notice Permissionless factory for native GMB↔token pools (one per token), so
/// they are discoverable. Anyone can create one. Third-party developer
/// infrastructure (see WGMB.sol) — not operated by the project, not for GMB.
contract GembaNativePoolFactory {
    mapping(address => address) public getPool; // token => native pool
    address[] public allPools;

    event NativePoolCreated(address indexed token, address pool, uint256 index);

    error ZeroAddress();
    error PoolExists();

    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }

    /// @notice Create the native GMB pool for `token`. Reverts if it already exists.
    function createPool(address token) external returns (address pool) {
        if (token == address(0)) revert ZeroAddress();
        if (getPool[token] != address(0)) revert PoolExists();
        pool = address(new GembaNativePool(token));
        getPool[token] = pool;
        allPools.push(pool);
        emit NativePoolCreated(token, pool, allPools.length - 1);
    }
}
