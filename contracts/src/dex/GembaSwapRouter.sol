// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFactory {
    function getPair(address, address) external view returns (address);
    function createPair(address, address) external returns (address);
}

interface IPair {
    function getReserves() external view returns (uint256, uint256);
    function mint(address) external returns (uint256);
    function burn(address) external returns (uint256, uint256);
    function swap(uint256, uint256, address) external;
}

interface IWGMB {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address, uint256) external returns (bool);
}

/// @title GembaSwapRouter
/// @notice Uniswap-V2-style periphery: add/remove liquidity and multi-hop swaps over
/// `GembaSwapFactory` pairs, with native-GMB convenience via `WGMB`.
/// Third-party developer infrastructure (see WGMB.sol) — not operated by the project,
/// not for GMB. Stateless; holds no funds between calls.
contract GembaSwapRouter {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable WGMB;

    error Expired();
    error InvalidPath();
    error InsufficientAAmount();
    error InsufficientBAmount();
    error InsufficientOutputAmount();
    error ExcessiveInputAmount();
    error InsufficientLiquidity();
    error InsufficientAmount();
    error NativeSendFailed();

    modifier ensure(uint256 deadline) {
        if (block.timestamp > deadline) revert Expired();
        _;
    }

    constructor(address factory_, address wgmb_) {
        factory = factory_;
        WGMB = wgmb_;
    }

    receive() external payable {
        // only accept native GMB from WGMB (on withdraw)
        if (msg.sender != WGMB) revert NativeSendFailed();
    }

    // --- library math ---

    function sortTokens(address tokenA, address tokenB) public pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        address pair = IFactory(factory).getPair(tokenA, tokenB);
        (uint256 r0, uint256 r1) = IPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (r0, r1) : (r1, r0);
    }

    /// @notice given an amount of A and reserves, the equivalent amount of B.
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        if (amountA == 0) revert InsufficientAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    /// @notice output amount for an input, with the 0.30% fee.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * 997;
        amountOut = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) public view returns (uint256[] memory amounts) {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // --- add liquidity ---

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (IFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                if (amountAOptimal < amountAMin) revert InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = IFactory(factory).getPair(tokenA, tokenB);
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = IPair(pair).mint(to);
    }

    function addLiquidityGMB(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountGMBMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountGMB, uint256 liquidity) {
        (amountToken, amountGMB) =
            _addLiquidity(token, WGMB, amountTokenDesired, msg.value, amountTokenMin, amountGMBMin);
        address pair = IFactory(factory).getPair(token, WGMB);
        IERC20(token).safeTransferFrom(msg.sender, pair, amountToken);
        IWGMB(WGMB).deposit{value: amountGMB}();
        IWGMB(WGMB).transfer(pair, amountGMB);
        liquidity = IPair(pair).mint(to);
        if (msg.value > amountGMB) _safeTransferNative(msg.sender, msg.value - amountGMB); // refund dust
    }

    // --- remove liquidity ---

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = IFactory(factory).getPair(tokenA, tokenB);
        IERC20(pair).safeTransferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IPair(pair).burn(to);
        (address token0, ) = sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountB < amountBMin) revert InsufficientBAmount();
    }

    function removeLiquidityGMB(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountGMBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountToken, uint256 amountGMB) {
        (amountToken, amountGMB) =
            removeLiquidity(token, WGMB, liquidity, amountTokenMin, amountGMBMin, address(this), deadline);
        IERC20(token).safeTransfer(to, amountToken);
        IWGMB(WGMB).withdraw(amountGMB);
        _safeTransferNative(to, amountGMB);
    }

    // --- swaps ---

    function _swap(uint256[] memory amounts, address[] calldata path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? IFactory(factory).getPair(output, path[i + 2]) : _to;
            IPair(IFactory(factory).getPair(input, output)).swap(amount0Out, amount1Out, to);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
        IERC20(path[0]).safeTransferFrom(msg.sender, IFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactGMBForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != WGMB) revert InvalidPath();
        amounts = getAmountsOut(msg.value, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
        IWGMB(WGMB).deposit{value: msg.value}();
        IWGMB(WGMB).transfer(IFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    function swapExactTokensForGMB(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WGMB) revert InvalidPath();
        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
        IERC20(path[0]).safeTransferFrom(msg.sender, IFactory(factory).getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        uint256 out = amounts[amounts.length - 1];
        IWGMB(WGMB).withdraw(out);
        _safeTransferNative(to, out);
    }

    function _safeTransferNative(address to, uint256 amount) internal {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
    }
}
