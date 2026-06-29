// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {GembaVotes} from "../../src/governance/GembaVotes.sol";
import {GembaTimelock} from "../../src/governance/GembaTimelock.sol";
import {GembaGovernor} from "../../src/governance/GembaGovernor.sol";
import {EmergencyPause} from "../../src/governance/EmergencyPause.sol";
import {FoundationTreasury} from "../../src/reserves/FoundationTreasury.sol";
import {BaseReserve} from "../../src/reserves/BaseReserve.sol";
import {PublicReserve} from "../../src/reserves/PublicReserve.sol";

/// @dev A backdoored reserve implementation an attacker would try to upgrade the
/// proxy to: it adds a `loot()` that drains the reserve to an arbitrary address.
/// The campaign proves an attacker can NEVER get this deployed behind the proxy
/// without passing the full Governor → Timelock → delay path with a supermajority.
contract BackdoorReserveV2 is FoundationTreasury {
    function loot(address payable to) external {
        (bool ok, ) = to.call{value: address(this).balance}("");
        require(ok, "loot failed");
    }
}

/// @title Track 1 — Treasury & Governance adversarial suite
/// @notice GembaBlockchain security campaign (security/README.md, Track 1). These
/// tests are the *attacker's* playbook against the §3 invariants — every test makes
/// an active theft/drain/governance-capture attempt that MUST be defeated. They
/// complement (do not duplicate) the per-contract unit tests by exercising the full
/// Governor→Timelock→Reserve stack and timing/replay/exclusion edges.
contract Track1TreasuryAttackTest is Test {
    GembaVotes votes;
    GembaTimelock timelock;
    GembaGovernor gov;
    FoundationTreasury reserve;

    address payable attacker = payable(makeAddr("attacker"));
    address pauser = makeAddr("pauser");

    uint48 constant VOTING_DELAY = 1;
    uint32 constant VOTING_PERIOD = 50;
    uint256 constant MIN_DELAY = 3600; // 1h timelock
    uint256 constant QUORUM = 40; // %
    uint256 constant SUPERMAJORITY = 66; // %

    function setUp() public {
        address[] memory empty = new address[](0);
        address[] memory open = new address[](1);
        open[0] = address(0); // anyone can execute after the delay
        timelock = new GembaTimelock(MIN_DELAY, empty, open, address(this));

        // Reserve is excluded from voting at genesis (audit finding #10 wiring).
        FoundationTreasury impl = new FoundationTreasury();
        bytes memory data = abi.encodeCall(FoundationTreasury.initialize, (address(timelock), pauser));
        reserve = FoundationTreasury(payable(address(new ERC1967Proxy(address(impl), data))));
        vm.deal(address(reserve), 10_000 ether);

        address[] memory excluded = new address[](1);
        excluded[0] = address(reserve);
        votes = new GembaVotes(address(timelock), excluded);
        gov = new GembaGovernor(votes, timelock, VOTING_DELAY, VOTING_PERIOD, 0, QUORUM, SUPERMAJORITY, QUORUM, SUPERMAJORITY);

        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(gov));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));
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

    function _proposeRelease(address payable to, uint256 amount)
        internal
        returns (uint256 id, address[] memory t, uint256[] memory v, bytes[] memory c, string memory d)
    {
        t = new address[](1);
        v = new uint256[](1);
        c = new bytes[](1);
        t[0] = address(reserve);
        c[0] = abi.encodeCall(BaseReserve.release, (to, amount));
        d = "release";
        id = gov.propose(t, v, c, d);
    }

    // ── ATTACK 1: flash-vote / buy-the-vote at voting time ───────────────────────
    // Acquire a huge vGMB stake AFTER the proposal snapshot and try to swing a live
    // vote. Must contribute 0 weight (ERC20Votes checkpoint at the snapshot block).
    function test_Attack_FlashVoteAtVoteTimeHasZeroWeight() public {
        address honest = _voter("honest", 1000 ether); // small honest base
        vm.roll(block.number + 1);

        // attacker self-deals: propose releasing the whole reserve to themselves
        vm.prank(attacker);
        (uint256 id, , , , ) = _proposeRelease(attacker, 10_000 ether);

        vm.roll(block.number + VOTING_DELAY + 1); // snapshot is now fixed

        // attacker mints 1,000,000 vGMB AFTER the snapshot — classic flash-vote
        vm.deal(attacker, 1_000_000 ether);
        vm.startPrank(attacker);
        votes.depositFor{value: 1_000_000 ether}(attacker);
        votes.delegate(attacker);
        assertEq(votes.getVotes(attacker), 1_000_000 ether, "has live balance");
        gov.castVote(id, 1); // For — but weight is read at the snapshot, where it was 0
        vm.stopPrank();

        // honest holder votes Against with its snapshot weight
        vm.prank(honest);
        gov.castVote(id, 0);

        (uint256 against, uint256 forV, ) = gov.proposalVotes(id);
        assertEq(forV, 0, "flash-acquired votes contribute zero");
        assertEq(against, 1000 ether, "only snapshot weight counts");

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Defeated), "self-deal defeated");
    }

    // ── ATTACK 2: bypass the Governor by scheduling directly on the Timelock ──────
    // The Timelock is the reserve owner. If anyone but the Governor could schedule(),
    // the whole delay/vote gate is moot. Only PROPOSER_ROLE (the Governor) may.
    function test_Attack_DirectTimelockScheduleReverts() public {
        bytes memory call = abi.encodeCall(BaseReserve.release, (attacker, 10_000 ether));
        vm.prank(attacker);
        vm.expectRevert(); // AccessControlUnauthorizedAccount (no PROPOSER_ROLE)
        timelock.schedule(address(reserve), 0, call, bytes32(0), bytes32(0), MIN_DELAY);

        // …and even the Governor cannot have an EOA execute an unscheduled op
        vm.prank(attacker);
        vm.expectRevert();
        timelock.execute(address(reserve), 0, call, bytes32(0), bytes32(0));
    }

    // ── ATTACK 3: replay / double-execute a queued proposal ──────────────────────
    function test_Attack_DoubleExecuteReverts() public {
        address whale = _voter("whale", 1000 ether);
        vm.roll(block.number + 1);
        (uint256 id, address[] memory t, uint256[] memory v, bytes[] memory c, string memory d) =
            _proposeRelease(payable(makeAddr("grantee")), 100 ether);
        vm.roll(block.number + VOTING_DELAY + 1);
        vm.prank(whale);
        gov.castVote(id, 1);
        vm.roll(block.number + VOTING_PERIOD + 1);
        gov.queue(t, v, c, keccak256(bytes(d)));
        vm.warp(block.timestamp + MIN_DELAY + 1);
        gov.execute(t, v, c, keccak256(bytes(d)));
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Executed));

        // replaying the exact same execution must fail (operation already done)
        vm.expectRevert();
        gov.execute(t, v, c, keccak256(bytes(d)));
    }

    // ── ATTACK 4: a reserve tries to vote for its own drain (reserves never vote) ──
    function test_Attack_ExcludedReserveCannotAcquireOrCastVotes() public {
        assertTrue(votes.excluded(address(reserve)), "reserve excluded at genesis");

        // reserve cannot mint itself voting power
        vm.deal(address(reserve), 11_000 ether);
        vm.prank(address(reserve));
        vm.expectRevert(GembaVotes.Excluded.selector);
        votes.depositFor{value: 1000 ether}(address(reserve));

        // nor can anyone transfer vGMB INTO the reserve
        address holder = _voter("holder", 500 ether);
        vm.prank(holder);
        vm.expectRevert(GembaVotes.Excluded.selector);
        votes.transfer(address(reserve), 1);

        assertEq(votes.getVotes(address(reserve)), 0, "reserve has zero votes, always");
    }

    // ── ATTACK 5: compromised PublicReserve granter — drain is bounded, then halted ──────
    // A stolen granter key is the §16.5 accepted risk. Prove the rolling-window cap
    // bounds the bleed to epochCap per window, and EmergencyPause stops it dead.
    function test_Attack_CompromisedGranterBoundedThenPaused() public {
        PublicReserve fImpl = new PublicReserve();
        // perGrantCap 1000, epochCap 1000/day → max bleed = 1000 GMB/day
        bytes memory init =
            abi.encodeCall(PublicReserve.initialize, (address(timelock), pauser, attacker, 1000 ether, 1000 ether, 1 days));
        PublicReserve faucet = PublicReserve(payable(address(new ERC1967Proxy(address(fImpl), init))));
        vm.deal(address(faucet), 1_000_000 ether);

        // attacker (the compromised granter) loots up to the window cap…
        vm.prank(attacker);
        faucet.grant(attacker, 1000 ether);
        // …and is then hard-stopped within the window, no matter how many calls
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(attacker);
            vm.expectRevert(PublicReserve.AboveEpochCap.selector);
            faucet.grant(attacker, 1 ether);
        }
        assertEq(attacker.balance, 1000 ether, "bleed bounded to one window cap");

        // incident response: guardian pauses → grants revert even in the next window
        vm.prank(pauser);
        faucet.pause();
        vm.warp(block.timestamp + 1 days);
        vm.prank(attacker);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        faucet.grant(attacker, 1000 ether);
        assertEq(attacker.balance, 1000 ether, "no further loss after pause");
    }

    // ── ATTACK 6: malicious UUPS upgrade to a backdoored impl — minority defeated ──
    // Upgrading the reserve to BackdoorReserveV2 (which has loot()) is only possible
    // via the Timelock. A minority attacker's proposal to do so cannot reach quorum +
    // supermajority, so the backdoor never lands behind the proxy.
    function test_Attack_MaliciousUpgradeProposalDefeatedForMinority() public {
        address honest = _voter("honest", 1000 ether); // 1000
        address atk = _voter("attacker-stake", 300 ether); // 300 (minority)
        vm.roll(block.number + 1);

        BackdoorReserveV2 evilImpl = new BackdoorReserveV2();
        address[] memory t = new address[](1);
        uint256[] memory v = new uint256[](1);
        bytes[] memory c = new bytes[](1);
        t[0] = address(reserve);
        c[0] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(evilImpl), "");
        string memory d = "evil upgrade";

        vm.prank(atk);
        uint256 id = gov.propose(t, v, c, d);
        vm.roll(block.number + VOTING_DELAY + 1);

        vm.prank(atk);
        gov.castVote(id, 1); // 300 For
        vm.prank(honest);
        gov.castVote(id, 0); // 1000 Against

        vm.roll(block.number + VOTING_PERIOD + 1);
        assertEq(uint8(gov.state(id)), uint8(IGovernor.ProposalState.Defeated), "backdoor upgrade defeated");

        // the proxy still points at the clean implementation: loot() is not callable
        vm.prank(attacker);
        (bool ok, ) = address(reserve).call(abi.encodeWithSignature("loot(address)", attacker));
        assertFalse(ok, "backdoor never deployed");
        assertEq(address(reserve).balance, 10_000 ether, "reserve intact");
    }
}
