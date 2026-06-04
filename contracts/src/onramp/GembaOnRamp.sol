// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GembaOnRamp (GembaPay)
/// @notice Stablecoin → GMB on-ramp (CLAUDE.md §13 Phase 6, §2). A buyer pays a
/// stablecoin and receives native GMB at a fixed, operator-set rate from a
/// pre-funded GMB pool. This is a one-way **fixed-rate sale** — we operate **no
/// DEX** and offer **no fiat redemption** (GMB is never bought back for fiat).
/// Proceeds recirculate (§2: founder stock sold for stablecoin to give cheaper
/// access). Follows docs/security-standards.md.
///
/// ┌─────────────────────────────────────────────────────────────────────────┐
/// │ MiCA GATE (docs/risks.md ADR-009 — HARD BLOCKER):                         │
/// │ `publicSaleEnabled` is **false by default**. Public buying is disabled    │
/// │ until it is explicitly enabled. **Enabling public sale on a public/main   │
/// │ network is BLOCKED until a written MiCA classification sign-off from a     │
/// │ Bulgarian fintech lawyer** (free transferability weakens the              │
/// │ limited-network exemption — ADR-001/009). The mechanics are built and     │
/// │ tested on devnet/testnet with the flag toggled by the operator; do NOT    │
/// │ ship it enabled to the public without that legal sign-off. Internal,      │
/// │ closed formula grants to institutions go through the Faucet (Phase 3) and │
/// │ are NOT gated here.                                                       │
/// └─────────────────────────────────────────────────────────────────────────┘
contract GembaOnRamp is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice the stablecoin accepted as payment (e.g. a USD stablecoin).
    IERC20 public immutable stablecoin;

    /// @notice agmb paid out per 1 smallest-unit of stablecoin, scaled by 1e18
    /// (so the operator can express fractional rates and absorb decimal diffs).
    /// gmbOut = stableIn * rate / 1e18.
    uint256 public rate;

    uint256 public constant RATE_PRECISION = 1e18;

    /// @notice MiCA gate. FALSE by default; public `buy()` reverts until enabled.
    /// Enabling for a public/main network is blocked until MiCA sign-off (ADR-009).
    bool public publicSaleEnabled;

    event Bought(address indexed buyer, uint256 stableIn, uint256 gmbOut);
    event RateSet(uint256 rate);
    event PublicSaleSet(bool enabled);
    event Funded(address indexed from, uint256 amount);
    event StableWithdrawn(address indexed to, uint256 amount);
    event GmbWithdrawn(address indexed to, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error PublicSaleDisabled();
    error RateNotSet();
    error InsufficientLiquidity();
    error NativeSendFailed();

    constructor(address owner_, IERC20 stablecoin_) Ownable(owner_) {
        if (owner_ == address(0) || address(stablecoin_) == address(0)) revert ZeroAddress();
        stablecoin = stablecoin_;
    }

    /// @notice Buy native GMB with `stableIn` of the stablecoin at the current rate.
    /// @dev CEI: validate, pull stablecoin (effect), then send GMB; `nonReentrant`.
    function buy(uint256 stableIn) external nonReentrant returns (uint256 gmbOut) {
        if (!publicSaleEnabled) revert PublicSaleDisabled(); // MiCA gate (ADR-009)
        if (stableIn == 0) revert ZeroAmount();
        if (rate == 0) revert RateNotSet();

        gmbOut = (stableIn * rate) / RATE_PRECISION;
        if (gmbOut == 0) revert ZeroAmount();
        if (address(this).balance < gmbOut) revert InsufficientLiquidity();

        // pull payment first (checked transfer), then deliver GMB
        stablecoin.safeTransferFrom(msg.sender, address(this), stableIn);
        (bool ok, ) = payable(msg.sender).call{value: gmbOut}("");
        if (!ok) revert NativeSendFailed();

        emit Bought(msg.sender, stableIn, gmbOut);
    }

    // --- operator controls (owner = founder/ops or governance) ---

    function setRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert ZeroAmount();
        rate = newRate;
        emit RateSet(newRate);
    }

    /// @notice Toggle public sale. Enabling on a public network is BLOCKED until a
    /// written MiCA sign-off from a Bulgarian fintech lawyer (ADR-009).
    function setPublicSaleEnabled(bool enabled) external onlyOwner {
        publicSaleEnabled = enabled;
        emit PublicSaleSet(enabled);
    }

    /// @notice Withdraw stablecoin proceeds (recirculate, §2).
    function withdrawStable(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        stablecoin.safeTransfer(to, amount);
        emit StableWithdrawn(to, amount);
    }

    /// @notice Withdraw unsold GMB from the pool.
    function withdrawGmb(address to, uint256 amount) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientLiquidity();
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
        emit GmbWithdrawn(to, amount);
    }

    /// @notice Fund the GMB sale pool with native GMB.
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }
}
