// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GembaOnRamp} from "../src/onramp/GembaOnRamp.sol";
import {MockStablecoin} from "./mocks/MockStablecoin.sol";

// malicious buyer that re-enters buy() from its receive()
contract OnRampReentrant {
    GembaOnRamp ramp;
    IERC20 stable;
    bool armed;

    constructor(GembaOnRamp r, IERC20 s) {
        ramp = r;
        stable = s;
    }

    function attack(uint256 amount) external {
        stable.approve(address(ramp), type(uint256).max);
        armed = true;
        ramp.buy(amount);
    }

    receive() external payable {
        if (armed) {
            armed = false;
            ramp.buy(1); // blocked by nonReentrant
        }
    }
}

contract OnRampTest is Test {
    GembaOnRamp ramp;
    MockStablecoin stable;
    address operator = makeAddr("operator"); // founder/ops or governance
    address buyer = makeAddr("buyer");
    uint256 constant RATE = 10 * 1e18; // 1 stablecoin unit -> 10 GMB

    function setUp() public {
        stable = new MockStablecoin();
        ramp = new GembaOnRamp(operator, IERC20(address(stable)));
        vm.deal(address(ramp), 1_000_000 ether); // funded GMB pool
        vm.prank(operator);
        ramp.setRate(RATE);
        stable.mint(buyer, 1000 ether);
    }

    // --- the MiCA gate (ADR-009) ---

    function test_PublicSaleDisabledByDefault() public {
        assertFalse(ramp.publicSaleEnabled(), "public sale must be OFF by default (MiCA gate)");
        vm.prank(buyer);
        stable.approve(address(ramp), type(uint256).max);
        vm.prank(buyer);
        vm.expectRevert(GembaOnRamp.PublicSaleDisabled.selector);
        ramp.buy(5 ether);
    }

    function test_OnlyOwnerEnablesPublicSale() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, buyer));
        ramp.setPublicSaleEnabled(true);
    }

    // --- the sale mechanics (devnet/testnet, flag enabled by the operator) ---

    function test_BuyDeliversGmbAtRate() public {
        vm.prank(operator);
        ramp.setPublicSaleEnabled(true);

        vm.startPrank(buyer);
        stable.approve(address(ramp), type(uint256).max);
        uint256 out = ramp.buy(5 ether); // 5 mUSD -> 50 GMB
        vm.stopPrank();

        assertEq(out, 50 ether);
        assertEq(buyer.balance, 50 ether, "buyer received GMB");
        assertEq(stable.balanceOf(address(ramp)), 5 ether, "ramp received stablecoin");
        assertEq(stable.balanceOf(buyer), 995 ether);
    }

    function test_BuyZeroReverts() public {
        vm.prank(operator);
        ramp.setPublicSaleEnabled(true);
        vm.prank(buyer);
        vm.expectRevert(GembaOnRamp.ZeroAmount.selector);
        ramp.buy(0);
    }

    function test_RateNotSetReverts() public {
        GembaOnRamp fresh = new GembaOnRamp(operator, IERC20(address(stable)));
        vm.deal(address(fresh), 100 ether);
        vm.prank(operator);
        fresh.setPublicSaleEnabled(true);
        stable.mint(buyer, 10 ether);
        vm.startPrank(buyer);
        stable.approve(address(fresh), type(uint256).max);
        vm.expectRevert(GembaOnRamp.RateNotSet.selector);
        fresh.buy(1 ether);
        vm.stopPrank();
    }

    function test_InsufficientLiquidityReverts() public {
        GembaOnRamp dry = new GembaOnRamp(operator, IERC20(address(stable)));
        vm.startPrank(operator);
        dry.setRate(RATE);
        dry.setPublicSaleEnabled(true);
        vm.stopPrank();
        // dry has no GMB
        vm.startPrank(buyer);
        stable.approve(address(dry), type(uint256).max);
        vm.expectRevert(GembaOnRamp.InsufficientLiquidity.selector);
        dry.buy(1 ether);
        vm.stopPrank();
    }

    function test_OwnerWithdrawsProceeds() public {
        vm.prank(operator);
        ramp.setPublicSaleEnabled(true);
        vm.startPrank(buyer);
        stable.approve(address(ramp), type(uint256).max);
        ramp.buy(10 ether);
        vm.stopPrank();

        vm.prank(operator);
        ramp.withdrawStable(operator, 10 ether);
        assertEq(stable.balanceOf(operator), 10 ether);
    }

    function test_BuyReentrancyBlocked() public {
        vm.prank(operator);
        ramp.setPublicSaleEnabled(true);
        OnRampReentrant attacker = new OnRampReentrant(ramp, IERC20(address(stable)));
        stable.mint(address(attacker), 100 ether);

        vm.expectRevert(); // re-entry repelled
        attacker.attack(5 ether);
    }
}
