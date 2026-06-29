// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

// EIP-1167 minimal-proxy clones: mass cheap deploys + delegatecall. Three flows:
//   • cloneDeterministic(salt) -> counterfactual address (harness predicts it, then init + call)
//   • cloneAndInit(v)          -> deploy + init + use in ONE tx (create-and-use-in-one-tx)
// All targets' entry points are unconditional => revert-safe.

contract CloneTarget {
    address public owner;
    uint256 public val;
    bool public initialized;
    uint256 public pings;

    event Initialized(address indexed owner, uint256 val);
    event Pinged(uint256 pings);

    function init(address o, uint256 v) external {
        require(!initialized, "already init");
        initialized = true; owner = o; val = v;
        emit Initialized(o, v);
    }
    function ping() external { pings += 1; emit Pinged(pings); }
}

contract CloneFactory {
    address public immutable implementation;
    address[] public clones;
    event Cloned(address indexed clone, address indexed by, bool deterministic);

    constructor(address impl) { require(impl != address(0), "impl"); implementation = impl; }

    function _deploy(bytes32 salt, bool deterministic) internal returns (address inst) {
        address impl = implementation; // copy immutable to a local (assembly can't read immutables)
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, impl))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            switch deterministic
            case 0 { inst := create(0, ptr, 0x37) }
            default { inst := create2(0, ptr, 0x37, salt) }
        }
        require(inst != address(0), "clone failed");
    }

    /// @notice Deterministic clone — its address is predictable client-side (CREATE2).
    function cloneDeterministic(bytes32 salt) external returns (address inst) {
        inst = _deploy(salt, true); clones.push(inst); emit Cloned(inst, msg.sender, true);
    }

    /// @notice Deploy a clone AND init AND use it, all in one tx (create-and-use-in-one-tx).
    function cloneAndInit(uint256 v) external returns (address inst) {
        inst = _deploy(0, false);
        CloneTarget(inst).init(msg.sender, v);
        CloneTarget(inst).ping();
        clones.push(inst);
        emit Cloned(inst, msg.sender, false);
    }

    function cloneCount() external view returns (uint256) { return clones.length; }

    /// @notice keccak of the EIP-1167 creation code — the harness uses this to predict the
    /// CREATE2 clone address (predicted == actual is asserted in the forge test).
    function cloneInitCodeHash() external view returns (bytes32 h) {
        address impl = implementation;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, impl))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            h := keccak256(ptr, 0x37)
        }
    }
}
