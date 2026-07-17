// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployGovernance} from "../script/DeployGovernance.s.sol";

/// @dev Exposes the internal env-driven exclusion-list builder so the EXCLUDE_EXTRA
/// parsing path (the mechanism behind "only validators vote at launch") is unit-tested,
/// not just trusted at deploy time.
contract DeployGovernanceHarness is DeployGovernance {
    function buildExclusions(address a, address b, address c, address d)
        external
        view
        returns (address[] memory)
    {
        return _excludedReserves(a, b, c, d);
    }
}

/// NOTE: one sequential test on purpose — process env vars are shared across
/// parallel-running tests, so separate EXCLUDE_EXTRA tests would race each other.
contract DeployGovernanceExclusionsTest is Test {
    DeployGovernanceHarness harness;
    address constant FAUCET = address(0xF1);
    address constant FOUNDATION = address(0xF2);
    address constant DAO = address(0xF3);
    address constant CONTINGENCY = address(0xF4);

    function setUp() public {
        harness = new DeployGovernanceHarness();
    }

    function _build() internal view returns (address[] memory) {
        return harness.buildExclusions(FAUCET, FOUNDATION, DAO, CONTINGENCY);
    }

    function test_excludeExtra_parsingPaths() public {
        // --- testnet path: EXCLUDE_EXTRA empty -> exactly the 4 reserve contracts ---
        vm.setEnv("EXCLUDE_EXTRA", "");
        address[] memory list = _build();
        assertEq(list.length, 4, "empty env must add nothing");
        assertEq(list[0], FAUCET);
        assertEq(list[1], FOUNDATION);
        assertEq(list[2], DAO);
        assertEq(list[3], CONTINGENCY);

        // --- mainnet path: every genesis-seeded holder appended after the reserves ---
        address founder = makeAddr("founder");
        address publicfaucet = makeAddr("publicfaucet");
        address val0 = makeAddr("val0");
        address val1 = makeAddr("val1");
        vm.setEnv(
            "EXCLUDE_EXTRA",
            string.concat(
                vm.toString(founder), ",", vm.toString(publicfaucet), ",",
                vm.toString(val0), ",", vm.toString(val1)
            )
        );
        list = _build();
        assertEq(list.length, 8, "4 reserves + 4 extras");
        assertEq(list[4], founder);
        assertEq(list[5], publicfaucet);
        assertEq(list[6], val0);
        assertEq(list[7], val1);

        // --- malformed input must NEVER yield a silent partial/empty extra list ---
        // (vm.envOr with an array default swallows parse errors — the strict vm.envAddress
        // path reverts instead; probed via low-level call because cheatcode reverts
        // cannot be caught by expectRevert)
        bytes memory callData =
            abi.encodeCall(DeployGovernanceHarness.buildExclusions, (FAUCET, FOUNDATION, DAO, CONTINGENCY));
        vm.setEnv("EXCLUDE_EXTRA", "0xnot-an-address");
        (bool okMalformed,) = address(harness).staticcall(callData);
        vm.setEnv("EXCLUDE_EXTRA", "0x1111111111111111111111111111111111111111,garbage");
        (bool okHalf,) = address(harness).staticcall(callData);
        vm.setEnv("EXCLUDE_EXTRA", ""); // clean up before asserting (env is process-global)
        assertFalse(okMalformed, "garbage list must revert, not silently exclude nobody");
        assertFalse(okHalf, "half-garbage list must revert, not truncate");
    }
}
