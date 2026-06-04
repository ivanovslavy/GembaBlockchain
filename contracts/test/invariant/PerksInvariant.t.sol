// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GembaTicketing} from "../../src/tickets/GembaTicketing.sol";
import {GembaPerks, IGembaTicketing} from "../../src/tickets/GembaPerks.sol";

/// Random bonus payments by random callers. Only the distributor's in-cap payments
/// should succeed; the handler reduces its expected balance ONLY for those, so any
/// unauthorized or over-cap payout that slipped through would drop the live balance
/// below expected and fail the invariant — i.e. no path drains the perks pool.
contract PerksHandler is Test {
    GembaPerks public perks;
    uint256 public expectedBalance;
    uint256 public maxBonus;
    address distributor;
    address[4] callers;

    constructor(GembaPerks perks_, address distributor_, uint256 initial) {
        perks = perks_;
        distributor = distributor_;
        expectedBalance = initial;
        maxBonus = perks_.maxBonus();
        callers = [distributor_, makeAddr("att1"), makeAddr("att2"), makeAddr("att3")];
    }

    function payBonus(uint256 callerSeed, address to, uint256 amount) public {
        address caller = callers[callerSeed % callers.length];
        amount = bound(amount, 0, 5000 ether);
        if (to == address(0) || to == address(perks)) return;

        bool authorized = (caller == distributor) && amount > 0 && amount <= maxBonus;

        vm.prank(caller);
        try perks.payBonus(to, amount) {
            if (authorized) expectedBalance -= amount;
            // an unauthorized success would leave expectedBalance too high -> caught
        } catch {}
    }
}

contract PerksInvariantTest is Test {
    GembaPerks perks;
    PerksHandler handler;
    uint256 constant INITIAL = 100000 ether;

    function setUp() public {
        GembaTicketing t = new GembaTicketing(address(this));
        address distributor = makeAddr("distributor");
        perks = new GembaPerks(address(this), IGembaTicketing(address(t)), 1000 ether);
        perks.grantRole(perks.DISTRIBUTOR_ROLE(), distributor);
        vm.deal(address(perks), INITIAL);
        handler = new PerksHandler(perks, distributor, INITIAL);
        targetContract(address(handler));
    }

    function invariant_OnlyAuthorizedBonusesLeavePool() public view {
        assertEq(address(perks).balance, handler.expectedBalance());
    }

    function invariant_NeverOverdraws() public view {
        assertLe(address(perks).balance, INITIAL);
    }
}
