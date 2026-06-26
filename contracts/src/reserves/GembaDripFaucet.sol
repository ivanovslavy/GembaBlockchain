// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {BaseReserve} from "./BaseReserve.sol";

/// @title GembaDripFaucet
/// @notice **MAINNET** drip faucet with an **on-chain per-recipient cooldown**.
///
/// The testnet faucet enforces its cooldown only in an off-chain service's memory, so a
/// service restart/redeploy/second-instance resets it (audit AU-2). On mainnet that is not
/// acceptable. This contract enforces the per-address cooldown **on-chain**, so it cannot be
/// bypassed by restarting or scaling the front-end service. The service still adds a per-IP
/// limit on top (one IP cannot farm many addresses) — IP is inherently off-chain — but the
/// on-chain cooldown + the on-chain min-balance floor are the durable, un-bypassable guards.
///
/// Reserve-grade like the other treasuries (BaseReserve): holds native GMB, owner = Timelock
/// (the only authority that can withdraw via `release` or change params), EmergencyPause can
/// halt drips, upgrades are governance + timelock only.
contract GembaDripFaucet is BaseReserve {
    /// @notice GMB sent per successful drip.
    uint256 public dripAmount;
    /// @notice seconds a given recipient must wait between drips (enforced on-chain).
    uint256 public cooldown;
    /// @notice never drip if it would take the reserve below this floor.
    uint256 public minBalance;
    /// @notice recipient => timestamp of its last drip.
    mapping(address => uint256) public lastDrip;

    event Dripped(address indexed recipient, address indexed caller, uint256 amount);
    event DripParamsUpdated(uint256 dripAmount, uint256 cooldown, uint256 minBalance);

    /// @notice recipient is still within its cooldown; retry at `retryAt`.
    error CooldownActive(uint256 retryAt);
    /// @notice dripping would take the faucet below `minBalance` (or it is empty).
    error FaucetExhausted();

    /// @param owner_ Timelock. @param pauser_ EmergencyPause. @param dripAmount_ GMB per drip.
    /// @param cooldown_ per-recipient wait (seconds). @param minBalance_ reserve floor.
    function initialize(address owner_, address pauser_, uint256 dripAmount_, uint256 cooldown_, uint256 minBalance_)
        external
        initializer
    {
        __BaseReserve_init(owner_, pauser_);
        if (dripAmount_ == 0) revert ZeroAmount();
        dripAmount = dripAmount_;
        cooldown = cooldown_;
        minBalance = minBalance_;
        emit DripParamsUpdated(dripAmount_, cooldown_, minBalance_);
    }

    /// @notice Claim a drip for yourself (caller pays gas).
    function claim() external {
        _drip(msg.sender);
    }

    /// @notice Drip to `recipient` — e.g. relayed by the faucet service so a brand-new
    /// address needs no GMB for gas. The cooldown is enforced **per recipient**, so relaying
    /// cannot bypass it. Anyone may call (giving is the faucet's purpose; the cooldown bounds it).
    function dripTo(address recipient) external {
        _drip(recipient);
    }

    /// @dev CEI + nonReentrant: check cooldown + floor, set lastDrip (effect), then send.
    function _drip(address recipient) internal whenNotPaused nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        // First-ever drip (lastDrip == 0) is always allowed; otherwise enforce the cooldown.
        uint256 last = lastDrip[recipient];
        if (last != 0 && block.timestamp < last + cooldown) revert CooldownActive(last + cooldown);
        uint256 amount = dripAmount;
        uint256 bal = address(this).balance;
        if (bal < amount || bal - amount < minBalance) revert FaucetExhausted();
        lastDrip[recipient] = block.timestamp;
        (bool ok, ) = payable(recipient).call{value: amount}("");
        if (!ok) revert NativeSendFailed();
        emit Dripped(recipient, msg.sender, amount);
    }

    /// @notice Governance (Timelock) tunes the drip parameters.
    function setDripParams(uint256 dripAmount_, uint256 cooldown_, uint256 minBalance_) external onlyOwner {
        if (dripAmount_ == 0) revert ZeroAmount();
        dripAmount = dripAmount_;
        cooldown = cooldown_;
        minBalance = minBalance_;
        emit DripParamsUpdated(dripAmount_, cooldown_, minBalance_);
    }

    /// @dev Storage gap (BaseReserve has its own).
    uint256[46] private __gapDrip;
}
