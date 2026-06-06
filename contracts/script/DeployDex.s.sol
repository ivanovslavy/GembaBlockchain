// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {WGMB} from "../src/dex/WGMB.sol";
import {GembaNativePoolFactory} from "../src/dex/GembaNativePoolFactory.sol";
import {LiquidityLocker} from "../src/dex/LiquidityLocker.sol";
import {DemoToken} from "../src/dex/examples/DemoToken.sol";
import {DemoFeeToken} from "../src/dex/examples/DemoFeeToken.sol";

/// @notice DEPLOY-ONLY: GembaSwap (1:1 Uniswap V2) + WGMB + native pool factory + locker +
/// two demo tokens. The live exercise (liquidity/swaps/lock) is ExerciseDex.s.sol — split
/// out because the big deploy txs and the small swap txs need different gas headroom under
/// the 10M block limit. Logs every contract address.
contract DeployDex is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address me = vm.addr(pk);
        vm.startBroadcast(pk);

        WGMB wgmb = new WGMB();
        address factory = deployCode("GembaSwapFactory.sol:GembaSwapFactory", abi.encode(me));
        address router = deployCode("GembaSwapRouter02.sol:GembaSwapRouter02", abi.encode(factory, address(wgmb)));
        GembaNativePoolFactory nativeFactory = new GembaNativePoolFactory();
        LiquidityLocker locker = new LiquidityLocker();
        DemoToken demo = new DemoToken("Gemba Demo Token", "DEMO", 1_000_000 ether);
        DemoFeeToken feeTok = new DemoFeeToken("Gemba Fee Demo", "FEEDEMO", 500, address(0xFEE5), 1_000_000 ether);

        vm.stopBroadcast();

        console2.log("WGMB", address(wgmb));
        console2.log("GembaSwapFactory", factory);
        console2.log("GembaSwapRouter02", router);
        console2.log("GembaNativePoolFactory", address(nativeFactory));
        console2.log("LiquidityLocker", address(locker));
        console2.log("DemoToken", address(demo));
        console2.log("DemoFeeToken", address(feeTok));
    }
}
