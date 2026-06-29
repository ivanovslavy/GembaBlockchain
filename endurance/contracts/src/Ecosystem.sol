// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "./Common.sol";

// EcosystemSim: a Bank + Token + Registry that call INTO each other in a single tx, so the
// endurance run exercises real cross-contract / multi-hop control flow (A -> B -> C):
//   EcoBank.deposit()  ->  EcoToken.reward()  ->  EcoRegistry.bump()
// All paths are revert-safe: deposit is unconditional (payable), withdraw is guarded
// client-side by the optimistically-tracked per-wallet balance (never withdraws more than
// it deposited), so the chain never sees a revert.

/// @notice Registry hit at the END of the multi-hop — records activity per user.
contract EcoRegistry {
    mapping(address => uint256) public actions; // user => count
    uint256 public totalActions;
    address public token; // only the reward token may bump (set once)

    event Bumped(address indexed user, uint256 userTotal, uint256 grandTotal);

    function setToken(address t) external { require(token == address(0), "set"); token = t; }
    function bump(address user) external {
        require(msg.sender == token, "only token");
        actions[user] += 1; totalActions += 1;
        emit Bumped(user, actions[user], totalActions);
    }
}

/// @notice Reward token in the middle of the multi-hop — mints to the user, then notifies
/// the registry (B -> C). Open mint via `reward`, only ever called by the bank in practice.
contract EcoToken {
    string public constant name = "Ecosystem Reward";
    string public constant symbol = "ECOR";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    EcoRegistry public immutable registry;
    event Transfer(address indexed from, address indexed to, uint256 value);

    constructor(EcoRegistry r) { registry = r; }

    /// @dev B -> C: mint reward then call the registry in the same tx.
    function reward(address to, uint256 weiIn) external {
        uint256 amt = weiIn * 1000; // 1000 reward units per wei deposited
        totalSupply += amt; balanceOf[to] += amt;
        emit Transfer(address(0), to, amt);
        registry.bump(to);
    }
}

/// @notice Bank — the entry point (A). deposit() is the multi-hop trigger; withdraw()
/// returns native GMB (guarded, CEI + nonReentrant).
contract EcoBank is ReentrancyGuard {
    EcoToken public immutable token;
    mapping(address => uint256) public balances; // native GMB credited per user
    uint256 public totalDeposits;

    error InsufficientBalance();

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(EcoToken t) { token = t; }

    /// @dev A -> B -> C in one tx: credit, then EcoToken.reward -> EcoRegistry.bump.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
        totalDeposits += msg.value;
        emit Deposited(msg.sender, msg.value);
        token.reward(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount > balances[msg.sender]) revert InsufficientBalance();
        balances[msg.sender] -= amount; // effects before interaction
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "send");
        emit Withdrawn(msg.sender, amount);
    }
}
