// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// FactoryAndCall: deploy fresh contracts DURING the run, then CALL functions on the freshly
// deployed child. Two deployment paths exercised by the workload:
//   1. EOA contract-creation tx (the worker deploys ChildCounter directly) — the child
//      address is CREATE(from, nonce), which the harness knows (it assigns the nonce).
//   2. MiniFactory.createChild(salt) — CREATE2 with a caller-supplied salt, so the child
//      address is deterministic (CREATE2(factory, salt, keccak(initcode))) and computable
//      client-side. childInitCodeHash() lets the harness read the exact hash on-chain.
// Both deployed children are then exercised via bump()/setValue() (unconditional => no revert).

/// @notice The freshly-deployed child. No constructor args => constant creation code (so its
/// CREATE2 address is predictable). All entry points are unconditional.
contract ChildCounter {
    address public creator;
    uint256 public value;

    event Bumped(uint256 newValue);

    constructor() { creator = msg.sender; }
    function bump() external { value += 1; emit Bumped(value); }
    function setValue(uint256 v) external { value = v; emit Bumped(v); }
}

/// @notice Deploys ChildCounter via CREATE2 with a caller-chosen (unique) salt.
contract MiniFactory {
    address[] public children;
    event ChildCreated(address indexed child, uint256 indexed salt, address indexed by);

    /// @dev salt must be globally unique (CREATE2 to an existing address reverts). The harness
    /// seeds the salt counter with a per-run random base so re-runs never collide.
    function createChild(uint256 salt) external returns (address child) {
        child = address(new ChildCounter{salt: bytes32(salt)}());
        children.push(child);
        emit ChildCreated(child, salt, msg.sender);
    }

    function childCount() external view returns (uint256) { return children.length; }

    /// @notice Exact keccak of ChildCounter's creation code — the harness uses this to predict
    /// the CREATE2 address (bulletproof against compiler/metadata drift).
    function childInitCodeHash() external pure returns (bytes32) { return keccak256(type(ChildCounter).creationCode); }
}
