// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {GembaFaucet} from "../../src/faucet/GembaFaucet.sol";
import {MockStablecoin} from "../mocks/MockStablecoin.sol";

/*//////////////////////////////////////////////////////////////
        MALICIOUS / ADVERSARIAL HELPER CONTRACTS
//////////////////////////////////////////////////////////////*/

/// @notice Attacker that re-enters claimGMB() from its receive() when the faucet pays it.
///         Proves the nonReentrant guard + CEI (cooldown set before send) defeat reentrancy.
contract ReentrantGmbClaimer {
    GembaFaucet public immutable faucet;
    bool private entered;
    uint256 public reentryAttempts;

    constructor(GembaFaucet f) { faucet = f; }

    function attack() external { faucet.claimGMB(); }

    receive() external payable {
        if (!entered) {
            entered = true;
            reentryAttempts++;
            faucet.claimGMB(); // re-enter while the outer claim is mid-flight
        }
    }
}

/// @notice A "token" whose mint() re-enters the faucet's claimToken(). Proves claimToken is
///         also reentrancy-safe even against a malicious/hostile token implementation.
contract ReentrantMintToken {
    GembaFaucet public faucet;
    bool private entered;
    uint256 public mintCalls;

    function setFaucet(GembaFaucet f) external { faucet = f; }

    function mint(address, uint256) external {
        mintCalls++;
        if (!entered) {
            entered = true;
            faucet.claimToken(address(this)); // re-enter
        }
    }
}

/// @notice A plain contract recipient that simply accepts GMB (no reentry) — must be able to claim.
contract PlainReceiver {
    GembaFaucet public immutable faucet;
    constructor(GembaFaucet f) { faucet = f; }
    function claim() external { faucet.claimGMB(); }
    receive() external payable {}
}

/// @notice A recipient that rejects native GMB — its own claim must revert (it only hurts itself).
contract RejectingReceiver {
    GembaFaucet public immutable faucet;
    constructor(GembaFaucet f) { faucet = f; }
    function claim() external { faucet.claimGMB(); }
    // no receive/fallback => cannot accept value
}

/*//////////////////////////////////////////////////////////////
                            TESTS
//////////////////////////////////////////////////////////////*/

contract GembaFaucetTest is Test {
    GembaFaucet faucet;
    MockStablecoin token;

    address owner = address(0xA11CE);
    address alice = address(0xA1);
    address bob = address(0xB0B);

    uint256 constant DRIP_GMB = 0.1 ether;
    uint256 constant DAILY_CAP = 100 ether;       // 1000 GMB-claims/day
    uint256 constant TOKEN_DRIP = 10_000e6;       // 10,000 (6-dec) per claim
    uint256 constant FUND = 1_000 ether;

    function setUp() public {
        vm.prank(owner);
        faucet = new GembaFaucet(owner, DRIP_GMB, DAILY_CAP);
        vm.deal(address(faucet), FUND);

        token = new MockStablecoin();
        vm.prank(owner);
        faucet.configureToken(address(token), true, TOKEN_DRIP);
    }

    /*------------------------------------------------------------
        HAPPY PATH
    ------------------------------------------------------------*/

    function test_ClaimGMB_paysDrip() public {
        uint256 before = alice.balance;
        vm.prank(alice);
        faucet.claimGMB();
        assertEq(alice.balance - before, DRIP_GMB, "drip not received");
        assertEq(faucet.gmbAvailableAt(alice), block.timestamp + 24 hours, "cooldown not set");
    }

    function test_ClaimToken_mintsDrip() public {
        vm.prank(alice);
        faucet.claimToken(address(token));
        assertEq(token.balanceOf(alice), TOKEN_DRIP, "token not minted");
    }

    /*------------------------------------------------------------
        COOLDOWN (anti-farming) — cannot be bypassed by retry
    ------------------------------------------------------------*/

    function test_ClaimGMB_cooldownBlocksSecondClaim() public {
        vm.prank(alice);
        faucet.claimGMB();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GembaFaucet.CooldownActive.selector, block.timestamp + 24 hours));
        faucet.claimGMB();
    }

    function test_ClaimGMB_worksAfterCooldown() public {
        vm.prank(alice);
        faucet.claimGMB();
        vm.warp(block.timestamp + 24 hours);
        vm.prank(alice);
        faucet.claimGMB(); // no revert
        assertEq(alice.balance, 2 * DRIP_GMB);
    }

    function test_ClaimToken_cooldownBlocksSecondClaim() public {
        vm.prank(alice);
        faucet.claimToken(address(token));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(GembaFaucet.CooldownActive.selector, block.timestamp + 24 hours));
        faucet.claimToken(address(token));
    }

    function test_ClaimToken_unsupportedReverts() public {
        vm.prank(alice);
        vm.expectRevert(GembaFaucet.TokenNotSupported.selector);
        faucet.claimToken(address(0xDEAD));
    }

    /*------------------------------------------------------------
        REENTRANCY — the core adversarial proof
    ------------------------------------------------------------*/

    /// claimGMB: a contract that re-enters from receive() cannot drain. The whole tx reverts and
    /// the attacker receives nothing; the faucet reserve is untouched.
    function test_Reentrancy_claimGMB_isDefeated() public {
        ReentrantGmbClaimer attacker = new ReentrantGmbClaimer(faucet);
        uint256 faucetBefore = address(faucet).balance;

        vm.expectRevert(); // sendValue fails because the re-entrant inner claim reverts
        attacker.attack();

        assertEq(address(attacker).balance, 0, "attacker drained funds!");
        assertEq(address(faucet).balance, faucetBefore, "faucet balance changed!");
    }

    /// claimToken: a hostile token whose mint() re-enters claimToken cannot double-mint.
    function test_Reentrancy_claimToken_isDefeated() public {
        ReentrantMintToken evil = new ReentrantMintToken();
        evil.setFaucet(faucet);
        vm.prank(owner);
        faucet.configureToken(address(evil), true, TOKEN_DRIP);

        vm.prank(alice);
        vm.expectRevert(); // inner re-entry hits nonReentrant -> mint reverts -> claimToken reverts
        faucet.claimToken(address(evil));

        assertEq(evil.mintCalls(), 0, "mint should have fully reverted (no successful state change)");
    }

    /// A non-reentrant contract recipient claims fine (proves we don't over-block legit contracts).
    function test_ContractRecipient_canClaim() public {
        PlainReceiver r = new PlainReceiver(faucet);
        r.claim();
        assertEq(address(r).balance, DRIP_GMB);
    }

    /// A recipient that rejects GMB only hurts itself (its claim reverts; faucet is fine).
    function test_RejectingRecipient_revertsItselfOnly() public {
        RejectingReceiver r = new RejectingReceiver(faucet);
        vm.expectRevert();
        r.claim();
        assertEq(address(faucet).balance, FUND, "faucet must be untouched");
    }

    /*------------------------------------------------------------
        GLOBAL DAILY CAP — sybil-drain protection (front-running bound)
    ------------------------------------------------------------*/

    /// Even an unlimited swarm of fresh addresses can take at most `gmbDailyCap` per window;
    /// the finite reserve can never be drained below balance - cap in a day.
    function test_DailyCap_boundsSybilDrain() public {
        vm.prank(owner);
        faucet.setGmbDailyCap(0.3 ether); // exactly 3 drips/window

        for (uint256 i = 0; i < 3; i++) {
            address sybil = address(uint160(0x1000 + i));
            vm.prank(sybil);
            faucet.claimGMB();
        }
        // 4th distinct address in the same window is capped out
        vm.prank(address(uint160(0x2000)));
        vm.expectRevert(GembaFaucet.DailyCapReached.selector);
        faucet.claimGMB();

        assertEq(faucet.gmbRemainingToday(), 0, "cap should be exhausted");
    }

    /// The cap window rolls over after 24h.
    function test_DailyCap_resetsAfterWindow() public {
        vm.prank(owner);
        faucet.setGmbDailyCap(0.1 ether); // 1 drip/window
        vm.prank(alice);
        faucet.claimGMB();
        vm.prank(bob);
        vm.expectRevert(GembaFaucet.DailyCapReached.selector);
        faucet.claimGMB();

        vm.warp(block.timestamp + 1 days);
        assertEq(faucet.gmbRemainingToday(), 0.1 ether, "window did not reset");
        vm.prank(bob);
        faucet.claimGMB(); // now allowed
    }

    /// Front-running is harmless: each address has its own cooldown, so an attacker front-running
    /// a victim's claim cannot steal the victim's drip — both addresses claim independently.
    function test_FrontRunning_perAddressIsolation() public {
        vm.prank(bob); // attacker front-runs
        faucet.claimGMB();
        vm.prank(alice); // victim still claims their own drip
        faucet.claimGMB();
        assertEq(alice.balance, DRIP_GMB);
        assertEq(bob.balance, DRIP_GMB);
    }

    function test_ClaimGMB_emptyReserveReverts() public {
        vm.prank(owner);
        faucet.withdrawGMB(payable(owner), FUND); // drain reserve (owner only)
        vm.prank(alice);
        vm.expectRevert(GembaFaucet.FaucetEmpty.selector);
        faucet.claimGMB();
    }

    /*------------------------------------------------------------
        ACCESS CONTROL — only the owner configures / recovers
    ------------------------------------------------------------*/

    function test_OnlyOwner_setGmbDrip() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.setGmbDrip(1 ether);
    }

    function test_OnlyOwner_setGmbDailyCap() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.setGmbDailyCap(1 ether);
    }

    function test_OnlyOwner_configureToken() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.configureToken(address(token), true, 1);
    }

    function test_OnlyOwner_withdrawGMB() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.withdrawGMB(payable(alice), 1 ether);
    }

    function test_OnlyOwner_recoverToken() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.recoverToken(address(token), alice, 1);
    }

    function test_OnlyOwner_pause() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.pause();
    }

    /*------------------------------------------------------------
        PAUSE — guardian can halt claims
    ------------------------------------------------------------*/

    function test_Pause_blocksClaims() public {
        vm.prank(owner);
        faucet.pause();
        vm.prank(alice);
        vm.expectRevert(); // EnforcedPause
        faucet.claimGMB();
        vm.prank(alice);
        vm.expectRevert();
        faucet.claimToken(address(token));

        vm.prank(owner);
        faucet.unpause();
        vm.prank(alice);
        faucet.claimGMB(); // works again
        assertEq(alice.balance, DRIP_GMB);
    }

    /*------------------------------------------------------------
        OWNERSHIP — two-step transfer cannot strand control
    ------------------------------------------------------------*/

    function test_Ownable2Step_transfer() public {
        vm.prank(owner);
        faucet.transferOwnership(alice);
        assertEq(faucet.owner(), owner, "ownership must not transfer until accepted");
        vm.prank(alice);
        faucet.acceptOwnership();
        assertEq(faucet.owner(), alice, "ownership not accepted");
    }

    /*------------------------------------------------------------
        FUZZ — drip & cap invariants
    ------------------------------------------------------------*/

    /// No claim ever pays more than the configured drip, and the reserve never goes negative.
    function testFuzz_ClaimNeverExceedsDrip(uint96 drip) public {
        drip = uint96(bound(drip, 1, 1 ether));
        vm.prank(owner);
        faucet.setGmbDrip(drip);
        vm.prank(owner);
        faucet.setGmbDailyCap(type(uint256).max);

        uint256 before = address(faucet).balance;
        vm.prank(alice);
        faucet.claimGMB();
        assertEq(before - address(faucet).balance, drip, "paid != drip");
        assertEq(alice.balance, drip);
    }
}
