// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title GembaNativePool
/// @notice A self-contained constant-product (x*y=k) AMM for **one ERC-20 token paired
/// with NATIVE GMB** — no WGMB wrapper. The pool holds native GMB directly (tracked in
/// `reserveNative`) and the ERC-20 on the other side; the contract itself is the ERC-20
/// LP token. 0.30% swap fee to LPs. User-facing add/remove/swap (no router needed).
/// This is the "pure GMB" variant of GembaSwap — for the WGMB/ERC-20-router path use
/// `GembaSwapRouter`. Third-party developer infrastructure (see WGMB.sol): not
/// operated by the project, not for GMB speculation. Follows docs/security-standards.md
/// (CEI + `nonReentrant`, SafeERC20, events, custom errors, fail loud).
contract GembaNativePool is ERC20, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    IERC20 public immutable token;
    uint256 public reserveToken;
    uint256 public reserveNative;

    event LiquidityAdded(address indexed to, uint256 amountToken, uint256 amountNative, uint256 liquidity);
    event LiquidityRemoved(address indexed to, uint256 amountToken, uint256 amountNative, uint256 liquidity);
    event Swap(address indexed sender, bool nativeIn, uint256 amountIn, uint256 amountOut, address indexed to);
    event Sync(uint256 reserveToken, uint256 reserveNative);

    error Expired();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientLiquidityMinted();
    error InsufficientTokenAmount();
    error InsufficientNativeAmount();
    error InsufficientOutputAmount();
    error InsufficientLiquidity();
    error NativeSendFailed();

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) revert Expired();
        _;
    }

    constructor(address token_) ERC20("GembaSwap Native LP", "GS-NLP") {
        if (token_ == address(0)) revert ZeroAddress();
        token = IERC20(token_);
    }

    function getReserves() external view returns (uint256 rToken, uint256 rNative) {
        return (reserveToken, reserveNative);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256) {
        if (amountA == 0) revert ZeroAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        return (amountA * reserveB) / reserveA;
    }

    /// @notice output for an input with the 0.30% fee.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256) {
        if (amountIn == 0) revert ZeroAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * 997;
        return (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function _update(uint256 rToken, uint256 rNative) private {
        reserveToken = rToken;
        reserveNative = rNative;
        emit Sync(rToken, rNative);
    }

    function _sendNative(address to, uint256 amount) private {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
    }

    // --- liquidity ---

    /// @notice Add liquidity. Send the native GMB side as `msg.value`; the token side
    /// is pulled via `transferFrom`. Unused native is refunded.
    function addLiquidity(
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline
    ) external payable nonReentrant ensure(deadline) returns (uint256 amountToken, uint256 amountNative, uint256 liquidity) {
        if (to == address(0)) revert ZeroAddress();
        uint256 nativeIn = msg.value;
        if (nativeIn == 0 || amountTokenDesired == 0) revert ZeroAmount();
        uint256 supply = totalSupply();

        // decide the token/native amounts to use at the optimal ratio (slippage-checked)
        if (supply == 0) {
            (amountToken, amountNative) = (amountTokenDesired, nativeIn);
        } else {
            uint256 nativeOptimal = quote(amountTokenDesired, reserveToken, reserveNative);
            if (nativeOptimal <= nativeIn) {
                if (nativeOptimal < amountNativeMin) revert InsufficientNativeAmount();
                (amountToken, amountNative) = (amountTokenDesired, nativeOptimal);
            } else {
                uint256 tokenOptimal = quote(nativeIn, reserveNative, reserveToken);
                if (tokenOptimal < amountTokenMin) revert InsufficientTokenAmount();
                (amountToken, amountNative) = (tokenOptimal, nativeIn);
            }
        }

        // pull the token and credit ONLY what actually arrived — fee-on-transfer / rebasing
        // safe, matching the Uniswap V2 pair's balanceOf-delta accounting (audit finding #7).
        uint256 balBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amountToken);
        amountToken = token.balanceOf(address(this)) - balBefore;
        if (amountToken == 0) revert ZeroAmount();

        if (supply == 0) {
            liquidity = Math.sqrt(amountToken * amountNative) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY);
        } else {
            // Re-quote the native side against the token amount ACTUALLY received: a
            // fee-on-transfer token shrinks `amountToken` on intake (above), so the
            // pre-pull `amountNative` would over-commit native relative to the LP minted
            // (audit finding F-2). Re-derive native at the true ratio and re-check the
            // slippage floor; `nativeNeeded <= nativeIn` always, so the excess is refunded
            // below. Standard ERC-20s are unaffected (amountToken unchanged => same native).
            uint256 nativeNeeded = quote(amountToken, reserveToken, reserveNative);
            if (nativeNeeded < amountNativeMin) revert InsufficientNativeAmount();
            amountNative = nativeNeeded;
            liquidity = Math.min((amountToken * supply) / reserveToken, (amountNative * supply) / reserveNative);
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();

        _update(reserveToken + amountToken, reserveNative + amountNative);
        _mint(to, liquidity);
        if (nativeIn > amountNative) _sendNative(msg.sender, nativeIn - amountNative); // refund dust
        emit LiquidityAdded(to, amountToken, amountNative, liquidity);
    }

    /// @notice Burn `liquidity` LP (held by the caller) and receive both sides.
    function removeLiquidity(
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountNativeMin,
        address to,
        uint256 deadline
    ) external nonReentrant ensure(deadline) returns (uint256 amountToken, uint256 amountNative) {
        if (to == address(0)) revert ZeroAddress();
        if (liquidity == 0) revert ZeroAmount();
        uint256 supply = totalSupply();
        amountToken = (liquidity * reserveToken) / supply;
        amountNative = (liquidity * reserveNative) / supply;
        if (amountToken == 0 || amountNative == 0) revert InsufficientLiquidity();
        if (amountToken < amountTokenMin) revert InsufficientTokenAmount();
        if (amountNative < amountNativeMin) revert InsufficientNativeAmount();

        _burn(msg.sender, liquidity); // effect before interactions (reverts if caller lacks LP)
        _update(reserveToken - amountToken, reserveNative - amountNative);
        token.safeTransfer(to, amountToken);
        _sendNative(to, amountNative);
        emit LiquidityRemoved(to, amountToken, amountNative, liquidity);
    }

    // --- swaps ---

    /// @notice Swap native GMB (`msg.value`) for the token.
    function swapExactNativeForTokens(uint256 amountOutMin, address to, uint256 deadline)
        external
        payable
        nonReentrant
        ensure(deadline)
        returns (uint256 amountOut)
    {
        if (to == address(0)) revert ZeroAddress();
        amountOut = getAmountOut(msg.value, reserveNative, reserveToken);
        if (amountOut == 0) revert InsufficientOutputAmount(); // fail loud on dust/rounding-to-zero (audit L-2)
        _update(reserveToken - amountOut, reserveNative + msg.value); // effects (K preserved: reserve drops by gross amountOut)
        uint256 balBefore = token.balanceOf(to);
        token.safeTransfer(to, amountOut); // interaction
        // Check amountOutMin against what the recipient ACTUALLY received, so a fee-on-transfer
        // output token cannot deliver less than promised (audit finding #3). For standard tokens
        // this equals amountOut. nonReentrant guards the post-transfer read.
        if (token.balanceOf(to) - balBefore < amountOutMin) revert InsufficientOutputAmount();
        emit Swap(msg.sender, true, msg.value, amountOut, to);
    }

    /// @notice Swap `amountIn` of the token for native GMB.
    function swapExactTokensForNative(uint256 amountIn, uint256 amountOutMin, address to, uint256 deadline)
        external
        nonReentrant
        ensure(deadline)
        returns (uint256 amountOut)
    {
        if (to == address(0)) revert ZeroAddress();
        if (amountIn == 0) revert ZeroAmount();
        // pull input first, then size the swap from what ACTUALLY arrived (FoT/rebasing safe, finding #7)
        uint256 balBefore = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amountIn); // pull input
        uint256 received = token.balanceOf(address(this)) - balBefore;
        amountOut = getAmountOut(received, reserveToken, reserveNative);
        if (amountOut == 0) revert InsufficientOutputAmount(); // fail loud on dust/rounding-to-zero (audit L-2)
        if (amountOut < amountOutMin) revert InsufficientOutputAmount();
        _update(reserveToken + received, reserveNative - amountOut); // effects
        _sendNative(to, amountOut); // interaction
        emit Swap(msg.sender, false, received, amountOut, to);
    }
}
