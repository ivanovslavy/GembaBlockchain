// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Faucet} from "../../src/reserves/Faucet.sol";

/// Drives the Faucet with random (caller, recipient, amount) sequences. Only the
/// owner (Timelock) and the granter are authorized; only the granter/owner path is
/// capped. The handler reduces its expected balance ONLY for authorized, in-cap
/// disbursements — so if any UNauthorized or over-cap call ever succeeds, the live
/// balance drops below the expected and the invariant fails.
contract FaucetHandler is Test {
    Faucet public faucet;
    address public timelock;
    address public granter;
    uint256 public expectedBalance;
    uint256 public cap;

    address[4] callers;

    constructor(Faucet f, address t, address g, uint256 initial) {
        faucet = f;
        timelock = t;
        granter = g;
        expectedBalance = initial;
        cap = f.perGrantCap();
        callers = [t, g, makeAddr("attacker1"), makeAddr("attacker2")];
    }

    function tryGrant(uint256 callerSeed, address to, uint256 amount) public {
        address caller = callers[callerSeed % callers.length];
        amount = bound(amount, 0, 5000 ether);
        if (to == address(0) || to == address(faucet)) return;

        bool authorized = (caller == timelock || caller == granter) && amount <= cap;

        vm.prank(caller);
        try faucet.grant(payable(to), amount) {
            if (authorized) expectedBalance -= amount;
            // if it succeeded while NOT authorized, expectedBalance is unchanged,
            // so the live balance will be lower -> the invariant catches it.
        } catch {}
    }

    function tryRelease(uint256 callerSeed, address to, uint256 amount) public {
        address caller = callers[callerSeed % callers.length];
        amount = bound(amount, 0, 5000 ether);
        if (to == address(0) || to == address(faucet)) return;

        bool authorized = (caller == timelock); // release is owner-only, uncapped

        vm.prank(caller);
        try faucet.release(payable(to), amount) {
            if (authorized) expectedBalance -= amount;
        } catch {}
    }
}

contract FaucetInvariantTest is Test {
    Faucet faucet;
    FaucetHandler handler;
    uint256 constant INITIAL = 100000 ether;

    function setUp() public {
        address timelock = makeAddr("timelock");
        address granter = makeAddr("granter");
        Faucet impl = new Faucet();
        bytes memory data = abi.encodeCall(Faucet.initialize, (timelock, makeAddr("pauser"), granter, 1000 ether));
        faucet = Faucet(payable(address(new ERC1967Proxy(address(impl), data))));
        vm.deal(address(faucet), INITIAL);

        handler = new FaucetHandler(faucet, timelock, granter, INITIAL);
        targetContract(address(handler));
    }

    /// The reserve balance is exactly the initial funding minus authorized,
    /// in-cap disbursements: no unauthorized or over-cap call can ever drain it.
    function invariant_OnlyAuthorizedDisbursements() public view {
        assertEq(address(faucet).balance, handler.expectedBalance());
    }

    /// The faucet never disburses more in total than it was funded.
    function invariant_NeverOverdraws() public view {
        assertLe(address(faucet).balance, INITIAL);
    }
}
