// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {EndERC20, EndERC721} from "../src/Tokens.sol";
import {CloneTarget, CloneFactory} from "../src/Clones.sol";
import {MiniVault, RewardStaking, IERC20D, IMintableD} from "../src/DeFi.sol";
import {AuctionHouse, IAucNFT} from "../src/Auctions.sol";
import {BatchMintNFT, NftStaking, RoyaltyNFT, RoyaltyMarket, IMintN} from "../src/NftExtras.sol";
import {MiniGov, GovTarget} from "../src/Governance.sol";
import {HopA, HopB, HopC, HopD, HopE, Disperse, EventsHeavy} from "../src/Composite.sol";
import {PermitToken, VoucherMinter} from "../src/SignedFlows.sol";
import {FeeOnTransferToken, RebasingToken} from "../src/EdgeTokens.sol";

// Proves every NEW endurance op family is revert-safe.
contract ExpansionTest is Test {
    address bob = address(0xB0B);
    receive() external payable {}

    // ---- EIP-1167 clones ----
    function test_Clones_create2_predict_init_call() public {
        CloneTarget impl = new CloneTarget();
        CloneFactory f = new CloneFactory(address(impl));
        // create-and-use-in-one-tx
        address inst = f.cloneAndInit(7);
        assertTrue(CloneTarget(inst).initialized());
        assertEq(CloneTarget(inst).pings(), 1);
        // deterministic: predicted == actual
        bytes32 salt = bytes32(uint256(0x1234));
        address predicted = vm.computeCreate2Address(salt, f.cloneInitCodeHash(), address(f));
        address det = f.cloneDeterministic(salt);
        assertEq(det, predicted);
        CloneTarget(det).init(address(this), 9);
        CloneTarget(det).ping();
        assertEq(CloneTarget(det).val(), 9);
    }

    // ---- ERC-4626-style vault ----
    function test_Vault_deposit_mint_withdraw_redeem() public {
        EndERC20 asset = new EndERC20("Asset", "AST");
        MiniVault v = new MiniVault(IERC20D(address(asset)));
        asset.mint(address(this), 1e24);
        asset.approve(address(v), type(uint256).max);
        v.deposit(1e18);
        v.mint(1e18);
        assertEq(v.balanceOf(address(this)), 2e18);
        v.withdraw(5e17);
        v.redeem(5e17);
        assertEq(v.balanceOf(address(this)), 1e18);
    }

    // ---- time-based reward staking ----
    function test_RewardStaking_stake_claim_unstake() public {
        EndERC20 stk = new EndERC20("Stake", "STK");
        EndERC20 rwd = new EndERC20("Reward", "RWD");
        RewardStaking rs = new RewardStaking(IERC20D(address(stk)), IMintableD(address(rwd)));
        stk.mint(address(this), 1e24);
        stk.approve(address(rs), type(uint256).max);
        rs.stake(1e18);
        vm.warp(block.timestamp + 100);
        rs.claim();
        assertGt(rwd.balanceOf(address(this)), 0);
        rs.unstake(4e17);
        (uint256 amt, ) = rs.positions(address(this));
        assertEq(amt, 6e17);
    }

    // ---- auctions ----
    function test_Auction_english_and_dutch() public {
        EndERC721 n = new EndERC721("Auc", "AUC");
        AuctionHouse h = new AuctionHouse(IAucNFT(address(n)));
        n.setApprovalForAll(address(h), true);
        // English
        n.mint(address(this), 1);
        h.createEnglish(1, 1e9, 100);
        vm.deal(bob, 1 ether);
        vm.prank(bob); h.bidEnglish{value: 1e9}(1);
        vm.warp(block.timestamp + 101);
        h.settleEnglish(1);
        assertEq(n.ownerOf(1), bob);
        // Dutch
        n.mint(address(this), 2);
        h.createDutch(2, 2e9, 1e8, 1000);
        vm.deal(bob, 1 ether);
        vm.prank(bob); h.buyDutch{value: 2e9}(2);
        assertEq(n.ownerOf(2), bob);
    }

    // ---- batch mint + NFT staking ----
    function test_BatchMint_and_NftStaking() public {
        BatchMintNFT n = new BatchMintNFT();
        EndERC20 rwd = new EndERC20("R", "R");
        NftStaking s = new NftStaking(n, IMintN(address(rwd)));
        n.mintBatch(address(this), 100, 5);
        assertEq(n.ownerOf(104), address(this));
        n.setApprovalForAll(address(s), true);
        s.stake(100);
        vm.warp(block.timestamp + 50);
        s.unstake(100);
        assertEq(n.ownerOf(100), address(this));
        assertGt(rwd.balanceOf(address(this)), 0);
    }

    // ---- royalty marketplace (EIP-2981) ----
    function test_RoyaltyMarket_list_buy_cancel() public {
        RoyaltyNFT n = new RoyaltyNFT();
        RoyaltyMarket m = new RoyaltyMarket(n);
        n.setApprovalForAll(address(m), true);
        n.mint(address(this), 1); // creator = this
        m.list(1, 1e9);
        vm.deal(bob, 1 ether);
        vm.prank(bob); m.buy{value: 1e9}(1);
        assertEq(n.ownerOf(1), bob);
        // cancel path
        n.mint(address(this), 2);
        m.list(2, 1e9);
        m.cancel(2);
        assertEq(n.ownerOf(2), address(this));
    }

    // ---- mini governance ----
    function test_Governance_lifecycle() public {
        MiniGov g = new MiniGov();
        GovTarget t = new GovTarget();
        g.propose(42, address(t));
        g.vote(42);
        vm.warp(block.timestamp + 41);
        g.queue(42);
        vm.warp(block.timestamp + 41);
        g.execute(42);
        assertEq(t.executed(), 1);
    }

    // ---- deep cross-contract chain + safe callback ----
    function test_DeepChain_and_callback() public {
        HopE e = new HopE();
        HopD d = new HopD(e);
        HopC c = new HopC(d);
        HopB b = new HopB(c);
        HopA a = new HopA(b);
        a.run();
        assertEq(e.c(), 1); // 5-hop reached the end
        a.runWithCallback();
        assertEq(a.callbacks(), 1);
    }

    function test_Disperse_and_EventsHeavy() public {
        Disperse d = new Disperse();
        address[] memory to = new address[](3);
        uint256[] memory amt = new uint256[](3);
        for (uint256 i; i < 3; i++) { to[i] = address(uint160(0x1000 + i)); amt[i] = 1; }
        d.disperseNative{value: 5}(to, amt); // overpay -> refund path
        EventsHeavy ev = new EventsHeavy();
        ev.emitMany(20);
        assertEq(ev.total(), 20);
    }

    // ---- EIP-2612 permit (ecrecover / EIP-712) ----
    function test_Permit_signed_then_delegated_transfer() public {
        PermitToken t = new PermitToken();
        uint256 ownerPk = 0xA11CE;
        address owner = vm.addr(ownerPk);
        t.mint(owner, 1e24);
        uint256 deadline = block.timestamp + 1000;
        bytes32 structHash = keccak256(abi.encode(t.PERMIT_TYPEHASH(), owner, bob, uint256(1e20), t.nonces(owner), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", t.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPk, digest);
        t.permit(owner, bob, 1e20, deadline, v, r, s);
        assertEq(t.allowance(owner, bob), 1e20);
        vm.prank(bob); t.transferFrom(owner, bob, 1e18);
        assertEq(t.balanceOf(bob), 1e18);
    }

    // ---- EIP-712 signed voucher ----
    function test_Voucher_signed_redeem() public {
        uint256 signerPk = 0xBEEF;
        VoucherMinter m = new VoucherMinter(vm.addr(signerPk));
        uint256 deadline = block.timestamp + 1000;
        bytes32 structHash = keccak256(abi.encode(m.VOUCHER_TYPEHASH(), bob, uint256(77), uint256(1e18), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", m.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        m.redeem(bob, 77, 1e18, deadline, v, r, s);
        assertEq(m.balanceOf(bob), 1e18);
    }

    // ---- edge tokens ----
    function test_EdgeTokens_fee_and_rebase() public {
        FeeOnTransferToken fot = new FeeOnTransferToken();
        fot.mint(address(this), 1e21);
        fot.transfer(bob, 1e20);
        assertEq(fot.balanceOf(bob), 1e20 - 1e18); // 1% fee
        RebasingToken rb = new RebasingToken();
        rb.mint(address(this), 1e21);
        uint256 before = rb.balanceOf(address(this));
        rb.rebase(1000); // +10%
        assertApproxEqAbs(rb.balanceOf(address(this)), before * 110 / 100, 1e6);
    }
}
