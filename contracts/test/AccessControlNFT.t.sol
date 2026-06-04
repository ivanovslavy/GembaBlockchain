// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AccessControlNFT} from "../src/access/AccessControlNFT.sol";

contract AccessControlNFTTest is Test {
    AccessControlNFT nft;
    address admin = makeAddr("admin"); // institution / governance
    address issuer = makeAddr("issuer"); // access-control admin
    address employee = makeAddr("employee");
    address other = makeAddr("other");
    uint256 constant ZONE_LAB = 7;
    bytes32 ISSUER;

    function setUp() public {
        nft = new AccessControlNFT(admin);
        ISSUER = nft.ISSUER_ROLE();
        vm.prank(admin);
        nft.grantRole(ISSUER, issuer);
    }

    function test_IssuerGrantsAndRevokes() public {
        vm.prank(issuer);
        nft.grantAccess(employee, ZONE_LAB);
        assertTrue(nft.hasAccess(employee, ZONE_LAB));

        vm.prank(issuer);
        nft.revokeAccess(employee, ZONE_LAB);
        assertFalse(nft.hasAccess(employee, ZONE_LAB));
    }

    function test_OnlyIssuerCanGrant() public {
        vm.prank(other);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, ISSUER)
        );
        nft.grantAccess(employee, ZONE_LAB);
    }

    function test_GrantZeroAddressReverts() public {
        vm.prank(issuer);
        vm.expectRevert(AccessControlNFT.ZeroAddress.selector);
        nft.grantAccess(address(0), ZONE_LAB);
    }

    function test_DoubleGrantReverts() public {
        vm.startPrank(issuer);
        nft.grantAccess(employee, ZONE_LAB);
        vm.expectRevert(AccessControlNFT.AlreadyGranted.selector);
        nft.grantAccess(employee, ZONE_LAB);
        vm.stopPrank();
    }

    function test_RevokeWithoutGrantReverts() public {
        vm.prank(issuer);
        vm.expectRevert(AccessControlNFT.NotGranted.selector);
        nft.revokeAccess(employee, ZONE_LAB);
    }

    function test_CapabilityIsSoulbound() public {
        vm.prank(issuer);
        nft.grantAccess(employee, ZONE_LAB);

        // an employee cannot transfer (sell/lend) their capability
        vm.prank(employee);
        vm.expectRevert(AccessControlNFT.Soulbound.selector);
        nft.safeTransferFrom(employee, other, ZONE_LAB, 1, "");
    }

    function test_GovernanceManagesIssuers() public {
        // admin can revoke an issuer; then it can no longer grant
        vm.prank(admin);
        nft.revokeRole(ISSUER, issuer);
        vm.prank(issuer);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, issuer, ISSUER)
        );
        nft.grantAccess(employee, ZONE_LAB);
    }
}
