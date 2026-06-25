// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GembaNativePool} from "../../src/dex/GembaNativePool.sol";
import {GembaNativePoolFactory} from "../../src/dex/GembaNativePoolFactory.sol";
import {DemoFeeToken} from "../../src/dex/examples/DemoFeeToken.sol";

/// Regression for pentest F-2: GembaNativePool.addLiquidity must re-quote the native
/// side against the token amount ACTUALLY received, so a fee-on-transfer token does not
/// make the depositor over-commit native relative to the LP minted.
contract F2NativePoolFoTTest is Test {
    GembaNativePool pool;
    DemoFeeToken feeToken;
    address alice = makeAddr("alice");
    uint256 constant DL = type(uint256).max;

    function setUp() public {
        GembaNativePoolFactory factory = new GembaNativePoolFactory();
        // 1% fee-on-transfer token
        feeToken = new DemoFeeToken("Fee", "FEE", 100, makeAddr("sink"), 0);
        feeToken.mint(alice, 1_000_000 ether);
        pool = GembaNativePool(factory.createPool(address(feeToken)));
        vm.deal(alice, 1_000 ether);

        // seed initial liquidity (supply == 0 branch)
        vm.startPrank(alice);
        feeToken.approve(address(pool), type(uint256).max);
        pool.addLiquidity{value: 100 ether}(10_000 ether, 0, 0, alice, DL);
        vm.stopPrank();
    }

    function test_F2_NativeRequotedAgainstReceivedToken() public {
        uint256 rT = pool.reserveToken();
        uint256 rN = pool.reserveNative();
        uint256 nativeBefore = alice.balance;

        // add more liquidity, supplying generous native; FoT shrinks the token on intake
        vm.prank(alice);
        (uint256 amountToken, uint256 amountNative, uint256 lp) =
            pool.addLiquidity{value: 50 ether}(1_000 ether, 0, 0, alice, DL);

        assertGt(lp, 0, "minted LP");
        // native committed must match the pool ratio at the RECEIVED token amount (the re-quote)
        assertApproxEqRel(amountNative * rT, amountToken * rN, 1e12, "native re-quoted to received-token ratio");
        // depositor only spent the re-quoted native — the rest was refunded (not over-committed)
        assertEq(nativeBefore - alice.balance, amountNative, "excess native refunded; no over-commit");
        assertLt(amountNative, 50 ether, "used less than supplied (FoT shrank the token side)");
    }
}
