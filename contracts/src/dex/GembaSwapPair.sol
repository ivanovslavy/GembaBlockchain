// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title GembaSwapPair
/// @notice Constant-product (x*y=k) AMM pool for one ERC-20 pair, Uniswap-V2-style,
/// ported to Solidity 0.8.x with the project's security standards. The pair token is
/// itself an ERC-20 LP token. 0.30% swap fee accrues to LPs. Created only by the
/// factory. (No TWAP oracle and no protocol fee — kept minimal for ecosystem dev
/// tooling; see WGMB.sol for the positioning note.)
contract GembaSwapPair is ERC20 {
    using SafeERC20 for IERC20;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;

    address public immutable factory;
    address public token0;
    address public token1;

    uint256 private reserve0;
    uint256 private reserve1;

    uint256 private _unlocked = 1;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint256 reserve0, uint256 reserve1);

    error Locked();
    error Forbidden();
    error AlreadyInitialized();
    error InsufficientLiquidityMinted();
    error InsufficientLiquidityBurned();
    error InsufficientOutputAmount();
    error InsufficientInputAmount();
    error InsufficientLiquidity();
    error InvalidTo();
    error K();

    modifier lock() {
        if (_unlocked != 1) revert Locked();
        _unlocked = 0;
        _;
        _unlocked = 1;
    }

    constructor() ERC20("GembaSwap LP", "GS-LP") {
        factory = msg.sender;
    }

    /// @dev Called once by the factory right after deployment.
    function initialize(address token0_, address token1_) external {
        if (msg.sender != factory) revert Forbidden();
        if (token0 != address(0)) revert AlreadyInitialized();
        token0 = token0_;
        token1 = token1_;
    }

    function getReserves() public view returns (uint256 r0, uint256 r1) {
        return (reserve0, reserve1);
    }

    function _update(uint256 balance0, uint256 balance1) private {
        reserve0 = balance0;
        reserve1 = balance1;
        emit Sync(balance0, balance1);
    }

    /// @notice Mint LP tokens to `to` for whatever tokens were transferred in since
    /// the last reserve sync. Called by the router after it sends both tokens here.
    function mint(address to) external lock returns (uint256 liquidity) {
        (uint256 r0, uint256 r1) = (reserve0, reserve1);
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - r0;
        uint256 amount1 = balance1 - r1;

        uint256 supply = totalSupply();
        if (supply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0xdead), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY
        } else {
            liquidity = Math.min((amount0 * supply) / r0, (amount1 * supply) / r1);
        }
        if (liquidity == 0) revert InsufficientLiquidityMinted();
        _mint(to, liquidity);
        _update(balance0, balance1);
        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice Burn the LP tokens this contract holds and send the underlying to `to`.
    /// The router transfers the LP here first, then calls burn.
    function burn(address to) external lock returns (uint256 amount0, uint256 amount1) {
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        uint256 supply = totalSupply();
        amount0 = (liquidity * balance0) / supply;
        amount1 = (liquidity * balance1) / supply;
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();
        _burn(address(this), liquidity);
        IERC20(token0).safeTransfer(to, amount0);
        IERC20(token1).safeTransfer(to, amount1);

        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /// @notice Low-level swap: send `amount{0,1}Out` to `to`, enforcing the
    /// constant-product invariant with a 0.30% fee on the input. The router transfers
    /// the input token in before calling this.
    function swap(uint256 amount0Out, uint256 amount1Out, address to) external lock {
        if (amount0Out == 0 && amount1Out == 0) revert InsufficientOutputAmount();
        (uint256 r0, uint256 r1) = (reserve0, reserve1);
        if (amount0Out >= r0 || amount1Out >= r1) revert InsufficientLiquidity();
        if (to == token0 || to == token1) revert InvalidTo();

        if (amount0Out > 0) IERC20(token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1).safeTransfer(to, amount1Out);

        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > r0 - amount0Out ? balance0 - (r0 - amount0Out) : 0;
        uint256 amount1In = balance1 > r1 - amount1Out ? balance1 - (r1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // 0.30% fee: balanceAdjusted = balance*1000 - amountIn*3
        uint256 balance0Adjusted = balance0 * 1000 - amount0In * 3;
        uint256 balance1Adjusted = balance1 * 1000 - amount1In * 3;
        if (balance0Adjusted * balance1Adjusted < r0 * r1 * (1000 * 1000)) revert K();

        _update(balance0, balance1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /// @notice Force reserves to match balances (recover from a donation/desync).
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)));
    }
}
