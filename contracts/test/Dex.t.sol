// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WGMB} from "../src/dex/WGMB.sol";
import {GembaSwapFactory} from "../src/dex/GembaSwapFactory.sol";
import {GembaSwapRouter} from "../src/dex/GembaSwapRouter.sol";
import {GembaNativePool} from "../src/dex/GembaNativePool.sol";
import {GembaNativePoolFactory} from "../src/dex/GembaNativePoolFactory.sol";
import {LiquidityLocker} from "../src/dex/LiquidityLocker.sol";

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract DexTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;
    WGMB wgmb;
    GembaSwapFactory factory;
    GembaSwapRouter router;
    GembaNativePoolFactory nativeFactory;
    LiquidityLocker locker;

    address alice = makeAddr("alice");
    uint256 constant DL = type(uint256).max;

    function setUp() public {
        tokenA = new MockERC20("Alpha", "ALPHA");
        tokenB = new MockERC20("Beta", "BETA");
        wgmb = new WGMB();
        factory = new GembaSwapFactory();
        router = new GembaSwapRouter(address(factory), address(wgmb));
        nativeFactory = new GembaNativePoolFactory();
        locker = new LiquidityLocker();

        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        vm.deal(alice, 1_000 ether);
    }

    // ---------------------------------------------------------------- native pool

    function test_NativePool_AddSwapRemove() public {
        GembaNativePool pool = GembaNativePool(nativeFactory.createPool(address(tokenA)));

        vm.startPrank(alice);
        tokenA.approve(address(pool), type(uint256).max);

        // seed 1000 ALPHA + 10 GMB
        (uint256 at, uint256 an, uint256 lp) = pool.addLiquidity{value: 10 ether}(1000 ether, 0, 0, alice, DL);
        assertEq(at, 1000 ether);
        assertEq(an, 10 ether);
        assertGt(lp, 0);
        (uint256 rt, uint256 rn) = pool.getReserves();
        assertEq(rt, 1000 ether);
        assertEq(rn, 10 ether);

        // swap 1 GMB -> ALPHA (pure native in)
        uint256 expOut = pool.getAmountOut(1 ether, rn, rt);
        uint256 balBefore = tokenA.balanceOf(alice);
        uint256 got = pool.swapExactNativeForTokens{value: 1 ether}(expOut, alice, DL);
        assertEq(got, expOut);
        assertEq(tokenA.balanceOf(alice) - balBefore, expOut);

        // swap ALPHA -> GMB (native out)
        (rt, rn) = pool.getReserves();
        uint256 expNative = pool.getAmountOut(100 ether, rt, rn);
        uint256 nativeBefore = alice.balance;
        uint256 gotNative = pool.swapExactTokensForNative(100 ether, expNative, alice, DL);
        assertEq(gotNative, expNative);
        assertEq(alice.balance - nativeBefore, expNative);

        // remove all liquidity
        uint256 lpBal = pool.balanceOf(alice);
        (uint256 outT, uint256 outN) = pool.removeLiquidity(lpBal, 0, 0, alice, DL);
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

    // ---------------------------------------------------------------- router (ERC20/ERC20)

    function test_Router_AddSwapRemove_ERC20() public {
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(address(tokenA), address(tokenB), 1000 ether, 4000 ether, 0, 0, alice, DL);
        address pair = factory.getPair(address(tokenA), address(tokenB));
        assertTrue(pair != address(0));

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        uint256[] memory expected = router.getAmountsOut(10 ether, path);
        uint256 bBefore = tokenB.balanceOf(alice);
        router.swapExactTokensForTokens(10 ether, expected[1], path, alice, DL);
        assertEq(tokenB.balanceOf(alice) - bBefore, expected[1]);

        uint256 lp = IERC20(pair).balanceOf(alice);
        IERC20(pair).approve(address(router), lp);
        (uint256 a, uint256 b) = router.removeLiquidity(address(tokenA), address(tokenB), lp, 0, 0, alice, DL);
        assertGt(a, 0);
        assertGt(b, 0);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- router (native via WGMB)

    function test_Router_NativeViaWGMB() public {
        vm.startPrank(alice);
        tokenA.approve(address(router), type(uint256).max);

        // ALPHA/GMB liquidity through the router (native -> WGMB internally)
        router.addLiquidityGMB{value: 10 ether}(address(tokenA), 1000 ether, 0, 0, alice, DL);
        address pair = factory.getPair(address(tokenA), address(wgmb));
        assertTrue(pair != address(0));

        // buy ALPHA with native GMB
        address[] memory path = new address[](2);
        path[0] = address(wgmb);
        path[1] = address(tokenA);
        uint256 aBefore = tokenA.balanceOf(alice);
        router.swapExactGMBForTokens{value: 1 ether}(0, path, alice, DL);
        assertGt(tokenA.balanceOf(alice) - aBefore, 0);

        // sell ALPHA for native GMB
        address[] memory back = new address[](2);
        back[0] = address(tokenA);
        back[1] = address(wgmb);
        uint256 nBefore = alice.balance;
        router.swapExactTokensForGMB(50 ether, 0, back, alice, DL);
        assertGt(alice.balance - nBefore, 0);
        vm.stopPrank();
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

        // extend (can only push later)
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
