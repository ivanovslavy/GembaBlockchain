// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// Proves the §41 regenesis property: contracts deployed via CREATE2 with a FIXED salt land at an
/// address that depends only on (deployer, salt, init-code) — NOT on the deployer's nonce or chain
/// history. So after a regenesis (a brand-new chain), redeploying the SAME bytecode with the SAME
/// salt from the SAME deployer yields the SAME address → every dApp config (CA) keeps working
/// untouched. (Plain `new C()` uses CREATE = nonce-dependent → addresses would shift on regenesis.)
contract Probe {
    uint256 public x;
    constructor(uint256 _x) { x = _x; }
}

contract Create2DeterminismTest is Test {
    function test_create2_addressIsDeterministic_nonceIndependent() public {
        bytes32 salt = keccak256("gemba.probe.v1");
        bytes memory initCode = abi.encodePacked(type(Probe).creationCode, abi.encode(uint256(42)));
        // Predicted purely from (this deployer, salt, init-code hash) — no nonce term.
        address predicted = vm.computeCreate2Address(salt, keccak256(initCode), address(this));

        // Bump this deployer's nonce a few times (simulating different chain history pre-deploy).
        new Probe(1);
        new Probe(2);

        Probe p = new Probe{salt: salt}(42);
        assertEq(address(p), predicted, "CREATE2 address must match the nonce-independent prediction");
        assertEq(p.x(), 42);
    }

    function test_create2_sameSaltSameCode_sameAddressAcrossDeployers_no() public {
        // Sanity: the address DOES depend on the deployer + salt (so a fixed deployer+salt is the
        // contract for reproducibility). Different salt => different address.
        bytes32 s1 = keccak256("gemba.governor.v1");
        bytes32 s2 = keccak256("gemba.timelock.v1");
        bytes memory code = abi.encodePacked(type(Probe).creationCode, abi.encode(uint256(7)));
        address a1 = vm.computeCreate2Address(s1, keccak256(code), address(this));
        address a2 = vm.computeCreate2Address(s2, keccak256(code), address(this));
        assertTrue(a1 != a2, "different salts => different addresses");
        // same salt+code+deployer => identical (the regenesis-preservation guarantee)
        assertEq(a1, vm.computeCreate2Address(s1, keccak256(code), address(this)));
    }
}
