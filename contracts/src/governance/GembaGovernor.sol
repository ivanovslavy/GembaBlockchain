// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title GembaGovernor
/// @notice Treasury/contract governance for GembaBlockchain (CLAUDE.md §7).
/// 1 vGMB = 1 vote (GembaVotes, reserves excluded). A proposal passes only with
/// BOTH a high quorum (GovernorVotesQuorumFraction, counting For + Abstain) AND a
/// SUPERMAJORITY of For over (For + Against) — set high (66–75%) for treasury and
/// upgrade actions (CLAUDE.md §7, "higher bar for treasury & upgrades"). Approved
/// proposals queue in the Timelock and execute only after the delay, by anyone.
contract GembaGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // --- two governance tiers (regenesis spec §9). A proposal is auto-classified at propose time
    // (the CODE decides, not a human): CRITICAL if it touches the Governor itself, the Timelock, or
    // a target governance flagged critical (staking/economic params, big treasury moves). Iron rule:
    // changing governance config targets the Governor/Timelock => always Critical, so nobody can lower
    // the bar via a "minor" proposal. Standard = 40% quorum / 51%; Critical = 51% quorum / 66%.
    /// @notice Standard-tier supermajority numerator out of 100 (For/(For+Against)).
    uint256 public immutable supermajorityNumerator;
    /// @notice Critical-tier quorum numerator out of quorumDenominator (For+Abstain / pastSupply).
    uint256 public immutable criticalQuorumNumerator;
    /// @notice Critical-tier supermajority numerator out of 100.
    uint256 public immutable criticalSupermajorityNumerator;
    /// @notice governance-flagged critical targets (staking/economic/treasury contracts). gov-tunable.
    mapping(address => bool) public criticalTarget;
    /// @notice tier captured at propose time: true = Critical.
    mapping(uint256 => bool) public isCritical;

    // SEC audit M3: function selectors that are ALWAYS Critical regardless of target. Prior to this,
    // criticalTarget[] was never populated at deploy, so a proposal to DRAIN a reserve
    // (release(...)) or UPGRADE a reserve to a fund-stealing implementation (upgradeToAndCall/
    // upgradeTo) targeted the reserve proxy — neither the Governor nor the Timelock nor flagged —
    // and passed at the Standard bar (40%/51%) instead of the Critical bar (51%/66%) the model
    // promises for treasury & upgrades (CLAUDE.md §7). Classifying by selector closes this even if
    // an operator forgets to flag a newly deployed reserve.
    bytes4 private constant SEL_UPGRADE_TO_AND_CALL = 0x4f1ef286; // upgradeToAndCall(address,bytes)
    bytes4 private constant SEL_UPGRADE_TO = 0x3659cfe6; // upgradeTo(address)
    bytes4 private constant SEL_RELEASE = 0x0357371d; // release(address,uint256)

    event CriticalTargetSet(address indexed target, bool critical);
    event ProposalTier(uint256 indexed proposalId, bool critical);

    error InvalidSupermajority();

    constructor(
        IVotes token_,
        TimelockController timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_,
        uint256 supermajorityNumerator_,
        uint256 criticalQuorumNumerator_,
        uint256 criticalSupermajorityNumerator_
    )
        Governor("GembaGovernor")
        GovernorSettings(votingDelay_, votingPeriod_, proposalThreshold_)
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(quorumNumerator_)
        GovernorTimelockControl(timelock_)
    {
        // both supermajorities must be a real majority and at most unanimous; critical >= standard.
        if (supermajorityNumerator_ < 51 || supermajorityNumerator_ > 100) revert InvalidSupermajority();
        if (criticalSupermajorityNumerator_ < supermajorityNumerator_ || criticalSupermajorityNumerator_ > 100) {
            revert InvalidSupermajority();
        }
        if (criticalQuorumNumerator_ < quorumNumerator_ || criticalQuorumNumerator_ > quorumDenominator()) {
            revert InvalidSupermajority();
        }
        supermajorityNumerator = supermajorityNumerator_;
        criticalQuorumNumerator = criticalQuorumNumerator_;
        criticalSupermajorityNumerator = criticalSupermajorityNumerator_;
    }

    /// @notice Governance flags/unflags a target as critical. The Governor + Timelock are ALWAYS
    /// critical (the iron rule), regardless of this map.
    function setCriticalTarget(address target, bool critical) external onlyGovernance {
        criticalTarget[target] = critical;
        emit CriticalTargetSet(target, critical);
    }

    /// @dev Capture the tier at propose time from the proposal's targets (the code decides).
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor) returns (uint256) {
        uint256 proposalId = super.propose(targets, values, calldatas, description);
        bool critical = false;
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(this) || targets[i] == _executor() || criticalTarget[targets[i]]) {
                critical = true;
                break;
            }
            // SEC audit M3: treasury exit / UUPS upgrade selectors are Critical regardless of target.
            bytes4 s = _selector(calldatas[i]);
            if (s == SEL_UPGRADE_TO_AND_CALL || s == SEL_UPGRADE_TO || s == SEL_RELEASE) {
                critical = true;
                break;
            }
        }
        isCritical[proposalId] = critical;
        emit ProposalTier(proposalId, critical);
        return proposalId;
    }

    /// @dev First 4 bytes (function selector) of a calldata blob; 0x00000000 if shorter.
    function _selector(bytes memory data) private pure returns (bytes4 s) {
        if (data.length < 4) return bytes4(0);
        assembly {
            s := mload(add(data, 0x20))
        }
    }

    /// @dev Tiered quorum: For+Abstain must reach the proposal's tier fraction of past total supply.
    function _quorumReached(uint256 proposalId) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        uint256 num = isCritical[proposalId] ? criticalQuorumNumerator : quorumNumerator();
        uint256 supply = token().getPastTotalSupply(proposalSnapshot(proposalId));
        uint256 threshold = (supply * num) / quorumDenominator();
        (, uint256 forVotes, uint256 abstainVotes) = proposalVotes(proposalId);
        return forVotes + abstainVotes >= threshold;
    }

    /// @dev Tiered supermajority: For must reach the tier's share of the decisive (For+Against) votes.
    function _voteSucceeded(uint256 proposalId) internal view override(Governor, GovernorCountingSimple) returns (bool) {
        (uint256 againstVotes, uint256 forVotes, ) = proposalVotes(proposalId);
        uint256 decisive = forVotes + againstVotes;
        if (decisive == 0) return false;
        uint256 sm = isCritical[proposalId] ? criticalSupermajorityNumerator : supermajorityNumerator;
        return forVotes * 100 >= decisive * sm;
    }

    // --- required multiple-inheritance overrides ---

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function quorum(uint256 timepoint) public view override(Governor, GovernorVotesQuorumFraction) returns (uint256) {
        return super.quorum(timepoint);
    }

    function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
