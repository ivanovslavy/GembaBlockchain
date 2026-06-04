// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";

import {GembaVotes} from "../src/governance/GembaVotes.sol";
import {GembaTimelock} from "../src/governance/GembaTimelock.sol";
import {GembaGovernor} from "../src/governance/GembaGovernor.sol";
import {FoundationTreasury} from "../src/reserves/FoundationTreasury.sol";
import {BaseReserve} from "../src/reserves/BaseReserve.sol";

/// End-to-end: a reserve's funds can leave ONLY via propose → vote (high quorum +
/// supermajority) → timelock delay → execute. No EOA, no shortcut.
contract GovernanceIntegrationTest is Test {
    GembaVotes votes;
    GembaTimelock timelock;
    GembaGovernor gov;
    FoundationTreasury reserve;

    address payable recipient = payable(makeAddr("grantee"));
    uint48 constant VOTING_DELAY = 1;
    uint32 constant VOTING_PERIOD = 50;
    uint256 constant MIN_DELAY = 3600; // 1h timelock
    uint256 constant QUORUM = 40; // %
    uint256 constant SUPERMAJORITY = 66; // %

    function setUp() public {
        // Timelock: no proposers yet, open executor, this test as temporary admin.
        address[] memory empty = new address[](0);
        address[] memory open = new address[](1);
        open[0] = address(0); // anyone can execute
        timelock = new GembaTimelock(MIN_DELAY, empty, open, address(this));

        votes = new GembaVotes(address(timelock));
        gov = new GembaGovernor(votes, timelock, VOTING_DELAY, VOTING_PERIOD, 0, QUORUM, SUPERMAJORITY);

        // Wire roles: governor proposes/cancels; then drop the admin so no EOA rules.
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(gov));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        // Reserve owned by the Timelock, funded.
        FoundationTreasury impl = new FoundationTreasury();
        bytes memory data = abi.encodeCall(FoundationTreasury.initialize, (address(timelock), makeAddr("pauser")));
        reserve = FoundationTreasury(payable(address(new ERC1967Proxy(address(impl), data))));
        vm.deal(address(reserve), 10000 ether);
    }

    function _voter(string memory name, uint256 amount) internal returns (address) {
        address v = makeAddr(name);
        vm.deal(v, amount);
        vm.startPrank(v);
        votes.depositFor{value: amount}(v);
        votes.delegate(v);
        vm.stopPrank();
        return v;
    }

    function _proposeRelease(uint256 amount)
        internal
        returns (uint256 id, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(reserve);
        values[0] = 0;
        calldatas[0] = abi.encodeCall(BaseReserve.release, (recipient, amount));
        desc = "release grant to institution";
        id = gov.propose(targets, values, calldatas, desc);
    }

    function test_FullLifecycle_PassesAndReleases() public {
        address whale = _voter("whale", 1000 ether); // 100% of supply
        vm.roll(block.number + 1);

        (uint256 id, address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) = _proposeRelease(500 ether);

        vm.roll(block.number + VOTING_DELAY + 1);
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Active));
        vm.prank(whale);
        gov.castVote(id, 1); // For

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Succeeded));

        gov.queue(t, v, c, keccak256(bytes(d)));
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Queued));

        // cannot execute before the timelock delay
        vm.expectRevert();
        gov.execute(t, v, c, keccak256(bytes(d)));

        vm.warp(block.timestamp + MIN_DELAY + 1);
        gov.execute(t, v, c, keccak256(bytes(d)));
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Executed));
        assertEq(recipient.balance, 500 ether, "reserve released funds via governance");
        assertEq(address(reserve).balance, 9500 ether);
    }

    function test_QuorumNotReached_Defeated() public {
        _voter("whale", 1300 ether); // total supply 2000, quorum = 800
        address small = _voter("small", 700 ether);
        vm.roll(block.number + 1);

        (uint256 id, , , , ) = _proposeRelease(1 ether);
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(small);
        gov.castVote(id, 1); // 700 For < 800 quorum

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Defeated), "quorum not reached");
    }

    function test_SupermajorityNotReached_Defeated() public {
        address a = _voter("a", 1000 ether);
        address b = _voter("b", 1000 ether); // total 2000, quorum 800
        vm.roll(block.number + 1);

        (uint256 id, , , , ) = _proposeRelease(1 ether);
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(a);
        gov.castVote(id, 1); // 1000 For
        vm.prank(b);
        gov.castVote(id, 0); // 1000 Against -> 50% < 66% supermajority

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Defeated), "supermajority not reached");
    }

    function test_DirectReserveCallByEOA_Reverts() public {
        // the whole point: no EOA can move reserve funds, only the Timelock
        vm.prank(makeAddr("eoa"));
        vm.expectRevert();
        reserve.release(recipient, 1 ether);
    }
}
