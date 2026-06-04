// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title AccessControlNFT
/// @notice Anonymous, **soulbound** capability tokens for workplace access
/// (CLAUDE.md §9, §10). A token id is a ZONE; holding a balance of 1 means
/// "this address may enter that zone". Door controllers read `hasAccess` on-chain.
///
/// **No PII on-chain (CLAUDE.md §10).** The contract knows only addresses and zone
/// ids — never names, employee ids, or logs. The identity↔address mapping and all
/// access logs live OFF-CHAIN in the access-control backend (PostgreSQL + RLS), so
/// the GDPR right to erasure can be honoured off-chain while the on-chain
/// capability stays verifiable and anonymous (see services/access-control).
///
/// Capabilities are **non-transferable** (soulbound): they are tied to a person's
/// wallet and may only be granted (mint) or revoked (burn) by an authorised
/// issuer — never traded. Follows docs/security-standards.md.
contract AccessControlNFT is ERC1155, AccessControl {
    /// @notice role allowed to grant/revoke capabilities (the institution's
    /// access-control admin; appointed by DEFAULT_ADMIN_ROLE = governance/institution).
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    event AccessGranted(address indexed holder, uint256 indexed zone, address indexed issuer);
    event AccessRevoked(address indexed holder, uint256 indexed zone, address indexed issuer);

    error ZeroAddress();
    error Soulbound();
    error AlreadyGranted();
    error NotGranted();

    /// @param admin the DEFAULT_ADMIN_ROLE holder (governance / the institution).
    constructor(address admin) ERC1155("") {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice Grant `holder` the capability to enter `zone`. Issuer only.
    function grantAccess(address holder, uint256 zone) external onlyRole(ISSUER_ROLE) {
        if (holder == address(0)) revert ZeroAddress();
        if (balanceOf(holder, zone) != 0) revert AlreadyGranted();
        _mint(holder, zone, 1, "");
        emit AccessGranted(holder, zone, msg.sender);
    }

    /// @notice Revoke `holder`'s capability for `zone`. Issuer only.
    function revokeAccess(address holder, uint256 zone) external onlyRole(ISSUER_ROLE) {
        if (balanceOf(holder, zone) == 0) revert NotGranted();
        _burn(holder, zone, 1);
        emit AccessRevoked(holder, zone, msg.sender);
    }

    /// @notice Does `holder` currently hold the capability for `zone`?
    function hasAccess(address holder, uint256 zone) external view returns (bool) {
        return balanceOf(holder, zone) != 0;
    }

    /// @dev Soulbound: allow only mint (from == 0) and burn (to == 0); block any
    /// holder-to-holder transfer. Capabilities cannot be traded (fail loud).
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override
    {
        if (from != address(0) && to != address(0)) revert Soulbound();
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
