// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {GembaVotes} from "../src/governance/GembaVotes.sol";
import {Faucet} from "../src/reserves/Faucet.sol";
import {EmergencyPause} from "../src/governance/EmergencyPause.sol";

/// Reentrancy-attack tests: every function that makes an external value/contract
/// call must repel a re-entrant caller (docs/security-standards.md §1).

// --- attacker that re-enters GembaVotes.withdrawTo from its receive() ---
contract VotesReentrant {
    GembaVotes votes;
    bool armed;

    constructor(GembaVotes v) {
        votes = v;
    }

    function wrapAndAttack() external payable {
        votes.depositFor{value: msg.value}(address(this));
        armed = true;
        votes.withdrawTo(address(this), msg.value); // native send -> receive() re-enters
    }

    receive() external payable {
        if (armed) {
            armed = false;
            votes.withdrawTo(address(this), 1 wei); // blocked by nonReentrant
        }
    }
}

// --- malicious granter that re-enters Faucet.grant from its receive() ---
contract GranterReentrant {
    Faucet faucet;
    bool armed;

    function setFaucet(Faucet f) external {
        faucet = f;
    }

    function attackGrant(uint256 amount) external {
        armed = true;
        faucet.grant(payable(address(this)), amount); // sends to itself -> receive() re-enters
    }

    receive() external payable {
        if (armed) {
            armed = false;
            faucet.grant(payable(address(this)), 1 wei); // blocked by nonReentrant
        }
    }
}

// --- malicious pausable target (also made a guardian) that re-enters confirm() ---
contract PausableReentrant {
    EmergencyPause guard;
    bool armed;

    function setGuard(EmergencyPause g) external {
        guard = g;
    }

    function pause() external {
        if (armed) {
            armed = false;
            guard.confirm(address(this), EmergencyPause.Op.Pause); // blocked by nonReentrant
        }
    }

    function unpause() external {}

    function attack() external {
        armed = true;
        guard.confirm(address(this), EmergencyPause.Op.Pause);
    }
}

contract ReentrancyTest is Test {
    function test_VotesWithdrawReentrancyBlocked() public {
        GembaVotes votes = new GembaVotes(makeAddr("gov"));
        VotesReentrant attacker = new VotesReentrant(votes);
        vm.deal(address(attacker), 10 ether);

        vm.expectRevert(); // re-entry is repelled -> the whole attack reverts
        attacker.wrapAndAttack{value: 5 ether}();

        // no funds extracted; the contract's backing is intact
        assertEq(address(votes).balance, votes.totalSupply());
    }

    function test_FaucetGrantReentrancyBlocked() public {
        GranterReentrant attacker = new GranterReentrant();
        Faucet impl = new Faucet();
        bytes memory data =
            abi.encodeCall(Faucet.initialize, (makeAddr("timelock"), makeAddr("pauser"), address(attacker), 1000 ether));
        Faucet faucet = Faucet(payable(address(new ERC1967Proxy(address(impl), data))));
        attacker.setFaucet(faucet);
        vm.deal(address(faucet), 100000 ether);

        vm.expectRevert(); // re-entry repelled
        attacker.attackGrant(100 ether);

        // the faucet was not drained beyond a single (failed) attempt
        assertEq(address(faucet).balance, 100000 ether);
    }

    function test_EmergencyPauseConfirmReentrancyBlocked() public {
        PausableReentrant target = new PausableReentrant();
        address[] memory gs = new address[](1);
        gs[0] = address(target); // the malicious target is the (single) guardian
        EmergencyPause guard = new EmergencyPause(makeAddr("gov"), gs, 1);
        target.setGuard(guard);

        vm.expectRevert(); // confirm -> target.pause() -> re-enter confirm -> nonReentrant reverts
        target.attack();
    }
}
