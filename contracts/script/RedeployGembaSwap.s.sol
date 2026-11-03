// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

interface IGembaSwapFactoryView {
    function feeToSetter() external view returns (address);
    function allPairsLength() external view returns (uint256);
}

interface IGembaSwapRouterView {
    function factory() external view returns (address);
    function WETH() external view returns (address);
}

/// @notice Redeploys ONLY GembaSwapFactory + GembaSwapRouter02 — needed whenever the pair
/// bytecode changes (2026-11-03: GPL headers + the LP token renamed 'GembaSwap V2'/'GSWAP-V2'
/// moved the pair init-code hash, and a router only finds pairs of a factory whose pair bytecode
/// matches the hash compiled into it). Everything else in the DEX set is independent of the
/// factory and is NOT redeployed: the existing WGMB is reused as the router's WETH, and the
/// native pool factory, locker and demo tokens stay where they are.
/// Env: DEPLOYER_PK (feeToSetter = deployer), WGMB (existing wrapped-GMB address).
/// The ABI is called through interfaces: the GPL-3.0 GembaSwap sources are deployed from their
/// artifacts (deployCode), not compiled into this Apache-2.0 script.
contract RedeployGembaSwap is Script {
    function run() external {
        uint256 pk = vm.envUint("DEPLOYER_PK");
        address me = vm.addr(pk);
        address wgmb = vm.envAddress("WGMB");
        require(wgmb.code.length > 0, "WGMB has no code on this chain");

        vm.startBroadcast(pk);
        address factory = deployCode("GembaSwapFactory.sol:GembaSwapFactory", abi.encode(me));
        address router = deployCode("GembaSwapRouter02.sol:GembaSwapRouter02", abi.encode(factory, wgmb));
        vm.stopBroadcast();

        require(IGembaSwapRouterView(router).factory() == factory, "router.factory mismatch");
        require(IGembaSwapRouterView(router).WETH() == wgmb, "router.WETH mismatch");
        require(IGembaSwapFactoryView(factory).feeToSetter() == me, "feeToSetter mismatch");

        console2.log("GembaSwapFactory", factory);
        console2.log("GembaSwapRouter02", router);
        console2.log("WGMB (reused)", wgmb);
        console2.log("pair init-code hash", vm.toString(keccak256(vm.getCode("GembaSwapPair.sol:GembaSwapPair"))));
    }
}
