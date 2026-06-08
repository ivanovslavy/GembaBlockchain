// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title GembaVotes (vGMB)
/// @notice The 1-GMB-1-vote token for treasury/contract governance (CLAUDE.md §7).
/// It wraps native GMB 1:1 — deposit native GMB to mint vGMB voting power, withdraw
/// to burn it back. Voting power is checkpointed (ERC20Votes), so governance reads
/// historical balances and cannot be gamed by a flash deposit at vote time.
///
/// Reserve/treasury contracts are EXPLICITLY excluded (CLAUDE.md §3.4, §7): an
/// excluded address can neither receive vGMB nor carry voting power, so reserves
/// never vote. The exclusion set is managed by governance (the Timelock).
contract GembaVotes is ERC20, ERC20Permit, ERC20Votes, ReentrancyGuard {
    /// @notice governance (the Timelock) — the only address that may change exclusions.
    address public immutable governance;

    /// @notice excluded (reserve) addresses: cannot hold vGMB, always 0 votes.
    mapping(address => bool) public excluded;

    event Wrapped(address indexed to, uint256 amount);
    event Unwrapped(address indexed to, uint256 amount);
    event ExclusionSet(address indexed account, bool excluded);

    error Excluded();
    error OnlyGovernance();
    error NativeSendFailed();
    error ZeroAddress();
    error ZeroAmount();

    /// @param _governance the Timelock (only address that may later change exclusions).
    /// @param initialExcluded reserve/treasury addresses to exclude from voting at genesis
    /// (audit finding #10 — wire the §3.4/§7 "reserves never vote" invariant at deploy,
    /// not just structurally). Governance can still add/remove later via `setExcluded`.
    constructor(address _governance, address[] memory initialExcluded)
        ERC20("Gemba Vote", "vGMB")
        ERC20Permit("Gemba Vote")
    {
        if (_governance == address(0)) revert ZeroAddress();
        governance = _governance;
        for (uint256 i = 0; i < initialExcluded.length; i++) {
            address a = initialExcluded[i];
            if (a != address(0)) {
                excluded[a] = true;
                emit ExclusionSet(a, true);
            }
        }
    }

    /// @notice Wrap native GMB into vGMB voting power credited to `to`.
    /// @dev No external call → CEI alone suffices; no `nonReentrant` needed.
    function depositFor(address to) external payable {
        if (to == address(0)) revert ZeroAddress();
        if (msg.value == 0) revert ZeroAmount();
        if (excluded[to]) revert Excluded();
        _mint(to, msg.value);
        emit Wrapped(to, msg.value);
    }

    /// @notice Burn vGMB and receive the underlying native GMB back.
    /// @dev CEI (burn before send) + `nonReentrant` guard on the external call.
    function withdrawTo(address to, uint256 amount) external nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _burn(msg.sender, amount);
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
        emit Unwrapped(to, amount);
    }

    /// @notice Governance marks/unmarks an address as an excluded reserve.
    function setExcluded(address account, bool isExcluded) external {
        if (msg.sender != governance) revert OnlyGovernance();
        excluded[account] = isExcluded;
        emit ExclusionSet(account, isExcluded);
    }

    // --- exclusion enforcement ---

    /// @dev Block sending vGMB to an excluded address (reserves can never hold it).
    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        if (to != address(0) && excluded[to]) revert Excluded();
        super._update(from, to, value);
    }

    /// @dev Excluded addresses carry zero current voting power (defense in depth).
    function getVotes(address account) public view override returns (uint256) {
        return excluded[account] ? 0 : super.getVotes(account);
    }

    /// @dev …and zero historical voting power.
    function getPastVotes(address account, uint256 timepoint) public view override returns (uint256) {
        return excluded[account] ? 0 : super.getPastVotes(account, timepoint);
    }

    // --- required multiple-inheritance overrides ---
    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
