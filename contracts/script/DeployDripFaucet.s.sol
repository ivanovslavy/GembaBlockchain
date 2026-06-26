// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GembaDripFaucet} from "../src/reserves/GembaDripFaucet.sol";

/// Deploys the MAINNET on-chain drip faucet (UUPS proxy, owner = Timelock). The per-address
/// cooldown is enforced on-chain, so a restart/redeploy of the front-end service cannot
/// bypass it (audit AU-2). Fund it after deploy; the service relays via `dripTo`.
///
///   FOUNDER_PK=.. TIMELOCK=0x.. EMERGENCY_PAUSE=0x.. \
///   DRIP_GMB=10 COOLDOWN_SECS=86400 MIN_BALANCE_GMB=1000 \
///   forge script script/DeployDripFaucet.s.sol --rpc-url <rpc> --broadcast
contract DeployDripFaucet is Script {
    function run() external {
        uint256 pk = vm.envUint("FOUNDER_PK");
        address timelock = vm.envAddress("TIMELOCK");
        address pause = vm.envAddress("EMERGENCY_PAUSE");
        // regenesis §8: 0.1 GMB per drip, once per day per address (the service adds the per-IP
        // limit). DRIP_WEI overrides for other amounts.
        uint256 drip = vm.envOr("DRIP_WEI", uint256(0.1 ether));
        uint256 cooldown = vm.envOr("COOLDOWN_SECS", uint256(1 days));
        uint256 minBal = vm.envOr("MIN_BALANCE_GMB", uint256(1000)) * 1 ether;

        vm.startBroadcast(pk);
        // CREATE2 (§41): salt the impl AND the proxy so both addresses survive a regenesis.
        GembaDripFaucet impl = new GembaDripFaucet{salt: keccak256(bytes("gemba.dripfaucet.impl.v1"))}();
        bytes memory data = abi.encodeCall(GembaDripFaucet.initialize, (timelock, pause, drip, cooldown, minBal));
        address faucet = address(new ERC1967Proxy{salt: keccak256(bytes("gemba.dripfaucet.v1"))}(address(impl), data));
        vm.stopBroadcast();

        console.log("GembaDripFaucet (proxy)", faucet, "owner=Timelock");
    }
}
