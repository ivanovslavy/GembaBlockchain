// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GembaVotes} from "../../src/governance/GembaVotes.sol";

/// Random wrap/unwrap/transfer sequences. Two invariants must always hold:
///  1. every vGMB is backed 1:1 by native GMB held in the contract, and
///  2. excluded (reserve) addresses can never accumulate a vGMB balance.
contract VotesHandler is Test {
    GembaVotes public votes;
    address public governance;
    address[3] public actors;
    address public excluded;

    constructor(GembaVotes v, address gov_, address excluded_) {
        votes = v;
        governance = gov_;
        excluded = excluded_;
        actors = [makeAddr("u1"), makeAddr("u2"), makeAddr("u3")];
    }

    function wrap(uint256 actorSeed, uint256 amount) public {
        address a = actors[actorSeed % actors.length];
        amount = bound(amount, 0, 100 ether);
        vm.deal(a, a.balance + amount);
        vm.prank(a);
        votes.depositFor{value: amount}(a);
    }

    function unwrap(uint256 actorSeed, uint256 amount) public {
        address a = actors[actorSeed % actors.length];
        uint256 bal = votes.balanceOf(a);
        if (bal == 0) return;
        amount = bound(amount, 0, bal);
        vm.prank(a);
        votes.withdrawTo(a, amount);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = actors[fromSeed % actors.length];
        // sometimes try to send to the excluded reserve (must always fail)
        address to = (toSeed % 4 == 0) ? excluded : actors[toSeed % actors.length];
        uint256 bal = votes.balanceOf(from);
        if (bal == 0) return;
        amount = bound(amount, 0, bal);
        vm.prank(from);
        try votes.transfer(to, amount) {} catch {}
    }
}

contract VotesInvariantTest is Test {
    GembaVotes votes;
    VotesHandler handler;
    address excluded = makeAddr("reserveExcluded");

    function setUp() public {
        address governance = makeAddr("governance");
        votes = new GembaVotes(governance);
        vm.prank(governance);
        votes.setExcluded(excluded, true);

        handler = new VotesHandler(votes, governance, excluded);
        targetContract(address(handler));
    }

    /// Every vGMB in existence is backed by native GMB in the contract.
    function invariant_FullyBacked() public view {
        assertEq(address(votes).balance, votes.totalSupply());
    }

    /// The excluded reserve can never hold voting tokens or votes.
    function invariant_ExcludedHoldsNothing() public view {
        assertEq(votes.balanceOf(excluded), 0);
        assertEq(votes.getVotes(excluded), 0);
    }
}
