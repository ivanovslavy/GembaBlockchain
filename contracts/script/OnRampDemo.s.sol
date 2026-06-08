// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GembaOnRamp} from "../src/onramp/GembaOnRamp.sol";
import {MockStablecoin} from "../test/mocks/MockStablecoin.sol";

/// @notice Live devnet demo of the GembaPay on-ramp (Phase 6). Shows the MiCA gate
/// (ADR-009): public sale is OFF by default; the operator enables it ON DEVNET
/// (blocked on mainnet until a written MiCA sign-off) and a buyer swaps stablecoin
/// for native GMB. Env: OPERATOR_PK (founder/ops), BUYER_PK (has a little GMB for gas).
contract OnRampDemo is Script {
    function run() external {
        uint256 opPk = vm.envUint("OPERATOR_PK");
        uint256 buyerPk = vm.envUint("BUYER_PK");
        address operator = vm.addr(opPk);
        address buyer = vm.addr(buyerPk);

        vm.startBroadcast(opPk);
        MockStablecoin stable = new MockStablecoin();
        GembaOnRamp ramp = new GembaOnRamp(operator, IERC20(address(stable)));
        (bool ok, ) = address(ramp).call{value: 100000 ether}(""); // fund GMB pool
        require(ok, "fund failed");
        ramp.setRate(10 * 1e18); // 1 stablecoin -> 10 GMB
        stable.mint(buyer, 1000 ether);
        vm.stopBroadcast();

        // MiCA gate: public sale is OFF by default.
        console.log("publicSaleEnabled by default (MiCA gate):", ramp.publicSaleEnabled());

        // Operator enables ON DEVNET (mainnet enabling blocked until MiCA sign-off).
        vm.broadcast(opPk);
        ramp.setPublicSaleEnabled(true);

        uint256 stableBefore = stable.balanceOf(buyer);
        uint256 gmbBefore = buyer.balance;

        // Buyer swaps 50 stablecoin -> 500 GMB.
        vm.startBroadcast(buyerPk);
        stable.approve(address(ramp), type(uint256).max);
        uint256 out = ramp.buy(50 ether, 0);
        vm.stopBroadcast();

        console.log("stablecoin paid (mUSD):", (stableBefore - stable.balanceOf(buyer)) / 1e18);
        console.log("GMB received          :", out / 1e18);
        console.log("buyer GMB delta       :", (buyer.balance - gmbBefore) / 1e18);
        console.log("ramp stablecoin held  :", stable.balanceOf(address(ramp)) / 1e18);
    }
}
