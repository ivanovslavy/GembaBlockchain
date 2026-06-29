// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "./Common.sol";

interface IERC20Min {
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address f, address to, uint256 a) external returns (bool);
}

// EnduranceStaking: deposit (stake) an ERC-20, withdraw it later. No rewards math (kept
// revert-safe and simple) — the point is to exercise stake/withdraw token flows under load.
//   - stake:    requires balance + allowance (both seeded once at funding) => never reverts.
//   - withdraw: guarded client-side by the optimistically-tracked staked amount => never
//               withdraws more than staked. CEI + nonReentrant.
contract EnduranceStaking is ReentrancyGuard {
    IERC20Min public immutable token;
    mapping(address => uint256) public staked;
    uint256 public totalStaked;

    error InsufficientStake();

    event Staked(address indexed user, uint256 amount, uint256 newBalance);
    event Withdrawn(address indexed user, uint256 amount, uint256 newBalance);

    constructor(IERC20Min token_) { token = token_; }

    function stake(uint256 amount) external nonReentrant {
        require(token.transferFrom(msg.sender, address(this), amount), "pull");
        staked[msg.sender] += amount;
        totalStaked += amount;
        emit Staked(msg.sender, amount, staked[msg.sender]);
    }

    function withdraw(uint256 amount) external nonReentrant {
        if (amount > staked[msg.sender]) revert InsufficientStake();
        staked[msg.sender] -= amount; // effects before interaction
        totalStaked -= amount;
        require(token.transfer(msg.sender, amount), "send");
        emit Withdrawn(msg.sender, amount, staked[msg.sender]);
    }
}
