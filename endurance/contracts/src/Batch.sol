// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// Batched multicall + SSTORE/compute targets — all unconditional => revert-safe.

interface IPingable { function ping() external; }

/// @notice A trivial counter target for the batch executor and the diamond-free ping ops.
contract Pinger {
    mapping(address => uint256) public pings;
    uint256 public total;
    event Pinged(address indexed who, uint256 userTotal);
    function ping() external { pings[msg.sender] += 1; total += 1; emit Pinged(msg.sender, pings[msg.sender]); }
}

/// @notice SSTORE / compute workbench (bounded keyspace, mod 1024) — gas-shaped variety.
contract Workbench {
    mapping(uint256 => uint256) public store;
    uint256 public counter;
    function set(uint256 key, uint256 val) external { store[key % 1024] = val; counter++; }
    function loop(uint256 n) external {
        uint256 x = counter;
        for (uint256 i = 0; i < n; i++) x = uint256(keccak256(abi.encode(x, i)));
        store[x % 1024] = x; counter++;
    }
}

/// @notice Executes many sub-calls in ONE tx (batched multicall). Points at safe targets
/// (the Pinger / a deployed child), so the aggregate tx never reverts.
contract BatchExecutor {
    uint256 public batches;
    event Batched(address indexed by, address indexed target, uint256 calls);

    /// @notice Call target.ping() `times` (bounded) in a single tx.
    function pingMany(address target, uint256 times) external {
        require(times <= 64, "too many");
        for (uint256 i = 0; i < times; i++) IPingable(target).ping();
        batches++;
        emit Batched(msg.sender, target, times);
    }

    /// @notice Generic aggregate of arbitrary calls (require each succeeds). The harness only
    /// ever points this at known-safe selectors, so it stays revert-free.
    function aggregate(address[] calldata targets, bytes[] calldata data) external returns (bytes[] memory results) {
        require(targets.length == data.length, "len");
        results = new bytes[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            (bool ok, bytes memory ret) = targets[i].call(data[i]);
            require(ok, "subcall");
            results[i] = ret;
        }
        batches++;
        emit Batched(msg.sender, targets.length > 0 ? targets[0] : address(0), targets.length);
    }
}
