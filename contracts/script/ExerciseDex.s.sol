// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GembaNativePool} from "../src/dex/GembaNativePool.sol";
import {GembaNativePoolFactory} from "../src/dex/GembaNativePoolFactory.sol";
import {LiquidityLocker} from "../src/dex/LiquidityLocker.sol";

interface IUniFactory {
    function getPair(address, address) external view returns (address);
}

interface IUniRouter {
    function addLiquidityETH(address, uint256, uint256, uint256, address, uint256)
        external
        payable
        returns (uint256, uint256, uint256);
    function removeLiquidity(address, address, uint256, uint256, uint256, address, uint256)
        external
        returns (uint256, uint256);
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
}

/// @notice EXERCISES the deployed GembaSwap live: 3 GMB liquidity (router/WGMB AND the
/// pure-native pool), buy + sell on both, fee-on-transfer token via the supporting path,
/// lock half the LP for ~4 min, remove (withdraw) the rest. Run with a high
/// --gas-estimate-multiplier (these are small txs; Cosmos EVM under-estimates swaps).
contract ExerciseDex is Script {
    uint256 constant DL = type(uint256).max;

    address me;
    address router;
    address factory;
    address wgmb;
    GembaNativePoolFactory nativeFactory;
    LiquidityLocker locker;
    address demo;
    address feeTok;
    address pair;
    address pool;
    uint256 lockId;
    uint256 unlockTime;

    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        me = vm.addr(pk);
        router = vm.envAddress("ROUTER");
        factory = vm.envAddress("FACTORY");
        wgmb = vm.envAddress("WGMB_ADDR");
        nativeFactory = GembaNativePoolFactory(vm.envAddress("NATIVE_FACTORY"));
        locker = LiquidityLocker(vm.envAddress("LOCKER"));
        demo = vm.envAddress("DEMO");
        feeTok = vm.envAddress("FEE");

        vm.startBroadcast(pk);
        IERC20(demo).approve(router, type(uint256).max);
        IERC20(feeTok).approve(router, type(uint256).max);
        _routerWGMB();
        _nativePool();
        _feeToken();
        vm.stopBroadcast();
        _report();
    }

    function _routerWGMB() internal {
        IUniRouter(router).addLiquidityETH{value: 3 ether}(demo, 1000 ether, 0, 0, me, DL);
        pair = IUniFactory(factory).getPair(demo, wgmb);

        address[] memory buyPath = new address[](2);
        buyPath[0] = wgmb;
        buyPath[1] = demo;
        IUniRouter(router).swapExactETHForTokens{value: 0.3 ether}(0, buyPath, me, DL);

        address[] memory sellPath = new address[](2);
        sellPath[0] = demo;
        sellPath[1] = wgmb;
        IUniRouter(router).swapExactTokensForETH(100 ether, 0, sellPath, me, DL);

        uint256 lp = IERC20(pair).balanceOf(me);
        uint256 lockAmt = lp / 2;
        IERC20(pair).approve(address(locker), lockAmt);
        unlockTime = block.timestamp + 240;
        lockId = locker.lock(pair, lockAmt, uint64(unlockTime));
        IERC20(pair).approve(router, lp - lockAmt);
        IUniRouter(router).removeLiquidity(demo, wgmb, lp - lockAmt, 0, 0, me, DL);
    }

    function _nativePool() internal {
        pool = nativeFactory.createPool(demo);
        IERC20(demo).approve(pool, type(uint256).max);
        GembaNativePool(pool).addLiquidity{value: 3 ether}(1000 ether, 0, 0, me, DL);
        GembaNativePool(pool).swapExactNativeForTokens{value: 0.3 ether}(0, me, DL);
        GembaNativePool(pool).swapExactTokensForNative(100 ether, 0, me, DL);
    }

    function _feeToken() internal {
        IUniRouter(router).addLiquidityETH{value: 2 ether}(feeTok, 1000 ether, 0, 0, me, DL);
        address[] memory fBuy = new address[](2);
        fBuy[0] = wgmb;
        fBuy[1] = feeTok;
        IUniRouter(router).swapExactETHForTokensSupportingFeeOnTransferTokens{value: 0.3 ether}(0, fBuy, me, DL);
        address[] memory fSell = new address[](2);
        fSell[0] = feeTok;
        fSell[1] = wgmb;
        IUniRouter(router).swapExactTokensForETHSupportingFeeOnTransferTokens(100 ether, 0, fSell, me, DL);
    }

    function _report() internal view {
        console2.log("DEMO_WGMB_pair", pair);
        console2.log("DEMO_NativePool", pool);
        console2.log("LockId", lockId);
        console2.log("LockUnlockTime", unlockTime);
    }
}
