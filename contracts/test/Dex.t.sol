// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WGMB} from "../src/dex/WGMB.sol";
import {GembaNativePool} from "../src/dex/GembaNativePool.sol";
import {GembaNativePoolFactory} from "../src/dex/GembaNativePoolFactory.sol";
import {LiquidityLocker} from "../src/dex/LiquidityLocker.sol";

// GembaSwap = a 1:1 rename of the official Uniswap V2 contracts (src/dex/gembaswap,
// core 0.5.16 / periphery 0.6.6), deployed here via vm.deployCode. Identical logic; only
// the names "UniswapV2"→"GembaSwap" and the pair init-code-hash in GembaSwapLibrary were
// changed (standard when deploying on a new chain). WETH = WGMB.
interface IUniFactory {
    function getPair(address, address) external view returns (address);
    function createPair(address, address) external returns (address);
}

interface IUniRouter {
    function factory() external view returns (address);
    function WETH() external view returns (address);
    function addLiquidity(address, address, uint256, uint256, uint256, uint256, address, uint256)
        external
        returns (uint256, uint256, uint256);
    function addLiquidityETH(address, uint256, uint256, uint256, address, uint256)
        external
        payable
        returns (uint256, uint256, uint256);
    function removeLiquidity(address, address, uint256, uint256, uint256, address, uint256)
        external
        returns (uint256, uint256);
    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256)
        external
        returns (uint256[] memory);
    function swapExactETHForTokens(uint256, address[] calldata, address, uint256)
        external
        payable
        returns (uint256[] memory);
    function swapExactTokensForETH(uint256, uint256, address[] calldata, address, uint256)
        external
        returns (uint256[] memory);
    function swapExactETHForTokensSupportingFeeOnTransferTokens(uint256, address[] calldata, address, uint256)
        external
        payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256, uint256, address[] calldata, address, uint256)
        external;
    function getAmountsOut(uint256, address[] calldata) external view returns (uint256[] memory);
}

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev ERC-20 that takes a 5% fee on every transfer — exercises the router's
/// fee-on-transfer-supporting swap path.
contract MockFeeERC20 is ERC20 {
    uint256 public constant FEE_BPS = 500; // 5%
    address public constant SINK = address(0xFEE);

    constructor() ERC20("Fee", "FEE") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 0) {
            uint256 fee = (value * FEE_BPS) / 10_000;
            super._update(from, SINK, fee);
            super._update(from, to, value - fee);
        } else {
            super._update(from, to, value);
        }
    }
}

contract DexTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;
    WGMB wgmb;
    IUniFactory factory;
    IUniRouter router;
    GembaNativePoolFactory nativeFactory;
    LiquidityLocker locker;

    address alice = makeAddr("alice");
    uint256 constant DL = type(uint256).max;

    function setUp() public {
        tokenA = new MockERC20("Alpha", "ALPHA");
        tokenB = new MockERC20("Beta", "BETA");
        wgmb = new WGMB();
        // GembaSwap (1:1 Uniswap V2), deployed from the 0.5.16/0.6.6 artifacts:
        factory = IUniFactory(deployCode("GembaSwapFactory.sol:GembaSwapFactory", abi.encode(address(this))));
        router = IUniRouter(
            deployCode("GembaSwapRouter02.sol:GembaSwapRouter02", abi.encode(address(factory), address(wgmb)))
        );
        nativeFactory = new GembaNativePoolFactory();
        locker = new LiquidityLocker();

        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        vm.deal(alice, 1_000 ether);
    }

    function test_OfficialRouter_Wiring() public view {
        assertEq(router.factory(), address(factory));
        assertEq(router.WETH(), address(wgmb));
    }

    // ---------------------------------------------------------------- official router: ERC20/ERC20

    function test_UniRouter_AddSwapRemove_ERC20() public {
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(address(tokenA), address(tokenB), 1000 ether, 4000 ether, 0, 0, alice, DL);
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256[] memory exp = router.getAmountsOut(10 ether, path);
        uint256 bBefore = tokenB.balanceOf(alice);
        router.swapExactTokensForTokens(10 ether, exp[1], path, alice, DL);
        assertEq(tokenB.balanceOf(alice) - bBefore, exp[1]);

        uint256 lp = IERC20(pair).balanceOf(alice);
        IERC20(pair).approve(address(router), lp);
        (uint256 a, uint256 b) = router.removeLiquidity(address(tokenA), address(tokenB), lp, 0, 0, alice, DL);
        assertGt(a, 0);
        assertGt(b, 0);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- official router: native (ETH=GMB via WGMB)

    function test_UniRouter_NativeETH() public {
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);

        router.addLiquidityETH{value: 10 ether}(address(tokenA), 1000 ether, 0, 0, alice, DL);
        address pair = factory.getPair(address(tokenA), address(wgmb));
        assertTrue(pair != address(0));

        // buy ALPHA with native GMB
        address[] memory path = new address[](2);
        path[0] = address(wgmb);
        path[1] = address(tokenA);
        uint256 aBefore = tokenA.balanceOf(alice);
        router.swapExactETHForTokens{value: 1 ether}(0, path, alice, DL);
        assertGt(tokenA.balanceOf(alice) - aBefore, 0);

        // sell ALPHA for native GMB
        address[] memory back = new address[](2);
        back[0] = address(tokenA);
        back[1] = address(wgmb);
        uint256 nBefore = alice.balance;
        router.swapExactTokensForETH(50 ether, 0, back, alice, DL);
        assertGt(alice.balance - nBefore, 0);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- official router: fee-on-transfer token

    function test_UniRouter_FeeOnTransferToken() public {
        MockFeeERC20 fee = new MockFeeERC20();
        fee.mint(alice, 1_000_000 ether);
        vm.startPrank(alice);
        fee.approve(address(router), type(uint256).max);

        router.addLiquidityETH{value: 10 ether}(address(fee), 1000 ether, 0, 0, alice, DL);

        address[] memory path = new address[](2);
        path[0] = address(wgmb);
        path[1] = address(fee);
        uint256 beforeBuy = fee.balanceOf(alice);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(0, path, alice, DL);
        assertGt(fee.balanceOf(alice) - beforeBuy, 0);

        address[] memory back = new address[](2);
        back[0] = address(fee);
        back[1] = address(wgmb);
        uint256 nBefore = alice.balance;
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(50 ether, 0, back, alice, DL);
        assertGt(alice.balance - nBefore, 0);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- pure-native pool (no WGMB)

    function test_NativePool_AddSwapRemove() public {
        GembaNativePool pool = GembaNativePool(nativeFactory.createPool(address(tokenA)));
        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);

        (uint256 at, uint256 an, uint256 lp) = pool.addLiquidity{value: 10 ether}(1000 ether, 0, 0, alice, DL);
        assertEq(at, 1000 ether);
        assertEq(an, 10 ether);
        assertGt(lp, 0);

        (uint256 rt, uint256 rn) = pool.getReserves();
        uint256 expOut = pool.getAmountOut(1 ether, rn, rt);
        uint256 balBefore = tokenA.balanceOf(alice);
        assertEq(pool.swapExactNativeForTokens{value: 1 ether}(expOut, alice, DL), expOut);
        assertEq(tokenA.balanceOf(alice) - balBefore, expOut);

        (rt, rn) = pool.getReserves();
        uint256 expNative = pool.getAmountOut(100 ether, rt, rn);
        uint256 nativeBefore = alice.balance;
        assertEq(pool.swapExactTokensForNative(100 ether, expNative, alice, DL), expNative);
        assertEq(alice.balance - nativeBefore, expNative);

        (uint256 outT, uint256 outN) = pool.removeLiquidity(pool.balanceOf(alice), 0, 0, alice, DL);
        assertGt(outT, 0);
        assertGt(outN, 0);
        vm.stopPrank();
    }

    function test_NativePool_RejectsZeroAndExpiry() public {
        GembaNativePool pool = GembaNativePool(nativeFactory.createPool(address(tokenA)));
        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        vm.expectRevert(GembaNativePool.Expired.selector);
        pool.addLiquidity{value: 1 ether}(1 ether, 0, 0, alice, 0);
        vm.expectRevert(GembaNativePool.ZeroAmount.selector);
        pool.addLiquidity{value: 0}(1 ether, 0, 0, alice, DL);
        vm.stopPrank();
    }

    function test_NativePoolFactory_OnePerToken() public {
        nativeFactory.createPool(address(tokenA));
        vm.expectRevert(GembaNativePoolFactory.PoolExists.selector);
        nativeFactory.createPool(address(tokenA));
    }

    // ---------------------------------------------------------------- liquidity locker

    function test_Locker_LockWithdrawExtend() public {
        GembaNativePool pool = GembaNativePool(nativeFactory.createPool(address(tokenA)));
        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        (, , uint256 lp) = pool.addLiquidity{value: 10 ether}(1000 ether, 0, 0, alice, DL);

        pool.approve(address(locker), lp);
        uint64 unlock = uint64(block.timestamp + 30 days);
        uint256 id = locker.lock(address(pool), lp, unlock);
        assertEq(pool.balanceOf(address(locker)), lp);

        vm.expectRevert(LiquidityLocker.StillLocked.selector);
        locker.withdraw(id);
        vm.expectRevert(LiquidityLocker.CannotShorten.selector);
        locker.extend(id, unlock - 1);
        locker.extend(id, unlock + 10 days);

        vm.warp(unlock + 11 days);
        locker.withdraw(id);
        assertEq(pool.balanceOf(alice), lp);
        vm.expectRevert(LiquidityLocker.AlreadyWithdrawn.selector);
        locker.withdraw(id);
        vm.stopPrank();
    }

    function test_Locker_RejectsPastUnlockAndNonOwner() public {
        GembaNativePool pool = GembaNativePool(nativeFactory.createPool(address(tokenA)));
        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);
        (, , uint256 lp) = pool.addLiquidity{value: 10 ether}(1000 ether, 0, 0, alice, DL);
        pool.approve(address(locker), lp);
        vm.expectRevert(LiquidityLocker.UnlockInPast.selector);
        locker.lock(address(pool), lp, uint64(block.timestamp));
        uint256 id = locker.lock(address(pool), lp, uint64(block.timestamp + 1 days));
        vm.stopPrank();

        vm.expectRevert(LiquidityLocker.NotLockOwner.selector);
        locker.withdraw(id);
    }
}
