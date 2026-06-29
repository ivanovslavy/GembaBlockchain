// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "./Common.sol";

interface IERC20D {
    function transfer(address to, uint256 a) external returns (bool);
    function transferFrom(address f, address to, uint256 a) external returns (bool);
    function balanceOf(address a) external view returns (uint256);
}
interface IMintableD { function mint(address to, uint256 a) external; }

// ERC-4626-style vault: deposit / mint / withdraw / redeem with proper share accounting.
// No yield mechanism, so shares:assets stays 1:1 — exact and revert-safe (the harness tracks
// shares as a credit and never redeems more than it holds).
contract MiniVault is ReentrancyGuard {
    IERC20D public immutable asset;
    string public name = "Endurance Vault Share";
    string public symbol = "evSHR";
    uint8 public constant decimals = 18;
    uint256 public totalSupply; // total shares
    mapping(address => uint256) public balanceOf; // shares per holder

    event Deposit(address indexed who, uint256 assets, uint256 shares);
    event Withdraw(address indexed who, uint256 assets, uint256 shares);

    constructor(IERC20D a) { asset = a; }

    function totalAssets() public view returns (uint256) { return asset.balanceOf(address(this)); }
    function convertToShares(uint256 assets) public view returns (uint256) { uint256 ts = totalSupply; uint256 ta = totalAssets(); return (ts == 0 || ta == 0) ? assets : assets * ts / ta; }
    function convertToAssets(uint256 shares) public view returns (uint256) { uint256 ts = totalSupply; return ts == 0 ? shares : shares * totalAssets() / ts; }

    function deposit(uint256 assets) external nonReentrant returns (uint256 shares) {
        shares = convertToShares(assets); require(shares > 0, "zero shares");
        require(asset.transferFrom(msg.sender, address(this), assets), "pull");
        balanceOf[msg.sender] += shares; totalSupply += shares;
        emit Deposit(msg.sender, assets, shares);
    }
    function mint(uint256 shares) external nonReentrant returns (uint256 assets) {
        assets = convertToAssets(shares); require(assets > 0, "zero assets");
        require(asset.transferFrom(msg.sender, address(this), assets), "pull");
        balanceOf[msg.sender] += shares; totalSupply += shares;
        emit Deposit(msg.sender, assets, shares);
    }
    function withdraw(uint256 shares) public nonReentrant returns (uint256 assets) {
        require(shares <= balanceOf[msg.sender], "shares");
        assets = convertToAssets(shares);
        balanceOf[msg.sender] -= shares; totalSupply -= shares; // effects before interaction
        require(asset.transfer(msg.sender, assets), "send");
        emit Withdraw(msg.sender, assets, shares);
    }
    function redeem(uint256 shares) external returns (uint256) { return withdraw(shares); }
}

// Staking with TIME-BASED reward accrual (block.timestamp). stake / claim / unstake. Rewards
// are minted from an open-mint reward token. Guarded: stake needs balance+allowance (seeded),
// claim is always valid (may mint 0), unstake is bounded by the harness-tracked staked amount.
contract RewardStaking is ReentrancyGuard {
    IERC20D public immutable stakeToken;
    IMintableD public immutable rewardToken;
    uint256 public constant REWARD_PER_SEC_PER_TOKEN = 1e6; // tiny: amount*sec*1e6/1e18

    struct Position { uint256 amount; uint256 since; }
    mapping(address => Position) public positions;
    uint256 public totalStaked;

    event Staked(address indexed who, uint256 amount);
    event Claimed(address indexed who, uint256 reward);
    event Unstaked(address indexed who, uint256 amount);

    constructor(IERC20D s, IMintableD r) { stakeToken = s; rewardToken = r; }

    function pending(address u) public view returns (uint256) {
        Position memory p = positions[u];
        if (p.amount == 0) return 0;
        return p.amount * (block.timestamp - p.since) * REWARD_PER_SEC_PER_TOKEN / 1e18;
    }
    function _settle(address u) internal { uint256 p = pending(u); positions[u].since = block.timestamp; if (p > 0) rewardToken.mint(u, p); }

    function stake(uint256 amount) external nonReentrant {
        _settle(msg.sender);
        require(stakeToken.transferFrom(msg.sender, address(this), amount), "pull");
        positions[msg.sender].amount += amount; totalStaked += amount;
        emit Staked(msg.sender, amount);
    }
    function claim() external nonReentrant { _settle(msg.sender); emit Claimed(msg.sender, 0); }
    function unstake(uint256 amount) external nonReentrant {
        require(amount <= positions[msg.sender].amount, "amount");
        _settle(msg.sender);
        positions[msg.sender].amount -= amount; totalStaked -= amount;
        require(stakeToken.transfer(msg.sender, amount), "send");
        emit Unstaked(msg.sender, amount);
    }
}
