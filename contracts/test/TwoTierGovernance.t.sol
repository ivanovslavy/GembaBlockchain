// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GembaVotes} from "../src/governance/GembaVotes.sol";
import {GembaTimelock} from "../src/governance/GembaTimelock.sol";
import {GembaGovernor} from "../src/governance/GembaGovernor.sol";
import {FoundationTreasury} from "../src/reserves/FoundationTreasury.sol";
import {BaseReserve} from "../src/reserves/BaseReserve.sol";

/// Regenesis §9: a proposal is auto-classified Standard (40%/51%) or Critical (51%/66%) by the CODE,
/// from its targets — no human decides. Critical = touches the Governor, the Timelock, or a
/// governance-flagged target. This proves the classification + the iron rule (gov-config = Critical).
contract TwoTierGovernanceTest is Test {
    GembaVotes votes;
    GembaTimelock timelock;
    GembaGovernor gov;
    FoundationTreasury reserve;

    uint48 constant VD = 1;
    uint32 constant VP = 50;
    uint256 constant MIN_DELAY = 3600;
    // Standard 40/51, Critical 51/66
    uint256 constant STD_Q = 40;
    uint256 constant STD_S = 51;
    uint256 constant CRIT_Q = 51;
    uint256 constant CRIT_S = 66;

    address voter = makeAddr("voter");

    function setUp() public {
        address[] memory empty = new address[](0);
        address[] memory open = new address[](1);
        open[0] = address(0);
        timelock = new GembaTimelock(MIN_DELAY, empty, open, address(this));
        votes = new GembaVotes(address(timelock), new address[](0));
        gov = new GembaGovernor(votes, timelock, VD, VP, 0, STD_Q, STD_S, CRIT_Q, CRIT_S);
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(gov));
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

        FoundationTreasury impl = new FoundationTreasury();
        reserve = FoundationTreasury(payable(address(new ERC1967Proxy(
            address(impl), abi.encodeCall(FoundationTreasury.initialize, (address(timelock), makeAddr("pauser")))))));

        // give the voter some power so it can propose
        vm.deal(voter, 1000 ether);
        vm.startPrank(voter);
        votes.depositFor{value: 1000 ether}(voter);
        votes.delegate(voter);
        vm.stopPrank();
        vm.roll(block.number + 1);
    }

    function _propose(address target, bytes memory cd, string memory desc) internal returns (uint256) {
        address[] memory t = new address[](1); t[0] = target;
        uint256[] memory v = new uint256[](1); v[0] = 0;
        bytes[] memory c = new bytes[](1); c[0] = cd;
        vm.prank(voter);
        return gov.propose(t, v, c, desc);
    }

    function test_params() public view {
        assertEq(gov.supermajorityNumerator(), STD_S);
        assertEq(gov.criticalQuorumNumerator(), CRIT_Q);
        assertEq(gov.criticalSupermajorityNumerator(), CRIT_S);
    }

    // SEC audit M3: a reserve DRAIN (release) is now Critical by selector, regardless of whether
    // the reserve target was flagged — closing the gap where treasury exits passed at Standard.
    function test_reserveRelease_isCritical() public {
        uint256 id = _propose(address(reserve),
            abi.encodeCall(BaseReserve.release, (payable(makeAddr("g")), 1 ether)), "release (critical)");
        assertTrue(gov.isCritical(id), "a reserve release must be Critical (treasury exit)");
    }

    // SEC audit M3: a UUPS upgrade of a reserve (which can install a fund-draining implementation)
    // is Critical by selector regardless of target.
    function test_reserveUpgrade_isCritical() public {
        uint256 id = _propose(address(reserve),
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", makeAddr("impl"), ""), "upgrade (critical)");
        assertTrue(gov.isCritical(id), "a reserve UUPS upgrade must be Critical");
    }

    // A non-treasury, non-upgrade call to an unflagged target stays Standard (tier still discriminates).
    function test_plainCall_isStandard() public {
        uint256 id = _propose(address(reserve),
            abi.encodeWithSignature("setPauser(address)", makeAddr("p")), "setPauser (standard)");
        assertFalse(gov.isCritical(id), "an ordinary unflagged call is Standard tier");
    }

    function test_governorTargeting_isCritical() public {
        // touching the Governor itself (e.g. flagging a critical target) => Critical (iron rule)
        uint256 id = _propose(address(gov),
            abi.encodeWithSignature("setCriticalTarget(address,bool)", address(reserve), true), "gov config");
        assertTrue(gov.isCritical(id), "changing governance config must be Critical");
    }

    function test_timelockTargeting_isCritical() public {
        uint256 id = _propose(address(timelock),
            abi.encodeWithSignature("updateDelay(uint256)", uint256(7200)), "timelock delay");
        assertTrue(gov.isCritical(id), "touching the Timelock must be Critical");
    }
}
