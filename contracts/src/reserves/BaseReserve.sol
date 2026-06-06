// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title BaseReserve
/// @notice Base for all GembaBlockchain reserve/treasury contracts (Foundation,
/// DAO, Contingency, Faucet). Holds native GMB and enforces the §3.6 invariant:
/// **no unilateral control of reserves.**
///
/// - **Upgradeable (UUPS):** the implementation can evolve, but the upgrade
///   authority is the **owner only**, which is set to the **Timelock** — never an
///   EOA (CLAUDE.md §9, docs/phase3-treasury-principles.md §2). Upgrades therefore
///   require propose → vote → timelock delay → execute.
/// - **Funds leave only via the owner (Timelock):** `release()` is `onlyOwner`, so
///   GMB moves out only through governance + delay.
/// - **Pausable, pause-only guardian:** the `EmergencyPause` guardian can pause
///   (halting `release`) but can NEVER move funds. Governance (owner) can also
///   unpause and can replace the guardian.
abstract contract BaseReserve is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @notice the EmergencyPause guardian (pause-only). Governance can replace it.
    address public pauser;

    event Released(address indexed to, uint256 amount);
    event PauserUpdated(address indexed previous, address indexed current);
    event Funded(address indexed from, uint256 amount);

    error OnlyPauser();
    error InsufficientBalance();
    error NativeSendFailed();
    error ZeroAddress();
    error ZeroAmount();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers(); // the implementation itself is never initialized
    }

    function __BaseReserve_init(address owner_, address pauser_) internal onlyInitializing {
        if (owner_ == address(0) || pauser_ == address(0)) revert ZeroAddress();
        __UUPSUpgradeable_init();
        __Ownable_init(owner_); // owner = Timelock (governance)
        __Pausable_init();
        __ReentrancyGuard_init();
        pauser = pauser_;
    }

    modifier onlyPauser() {
        if (msg.sender != pauser) revert OnlyPauser();
        _;
    }

    /// @notice Move native GMB out of the reserve. Owner (Timelock) only, and not
    /// while paused. This is the single exit for funds (§3.6).
    function release(address payable to, uint256 amount) external virtual onlyOwner whenNotPaused nonReentrant {
        _release(to, amount);
    }

    /// @dev Single validated exit for native value. Validates inputs first, then
    /// the external call last (CEI). All callers (`release`, `Faucet.grant`) are
    /// `nonReentrant`, so the post-call event is safe.
    function _release(address payable to, uint256 amount) internal {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientBalance();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert NativeSendFailed();
        emit Released(to, amount);
    }

    /// @notice Guardian halts the reserve during an incident. Cannot move funds.
    function pause() external onlyPauser {
        _pause();
    }

    /// @notice Guardian or governance lifts the pause.
    function unpause() external {
        if (msg.sender != pauser && msg.sender != owner()) revert OnlyPauser();
        _unpause();
    }

    /// @notice Governance (Timelock) replaces the emergency guardian.
    function setPauser(address newPauser) external onlyOwner {
        if (newPauser == address(0)) revert ZeroAddress();
        emit PauserUpdated(pauser, newPauser);
        pauser = newPauser;
    }

    /// @dev Upgrade authority is the owner (Timelock) and nothing else.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /// @notice Accept native GMB (e.g. the faucet's 40% fee inflow, or funding).
    receive() external payable {
        emit Funded(msg.sender, msg.value);
    }

    /// @dev Storage gap for safe future upgrades.
    uint256[49] private __gap;
}
