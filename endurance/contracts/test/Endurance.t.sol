// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {EndERC20, EndERC721, EndERC1155} from "../src/Tokens.sol";
import {EcoRegistry, EcoToken, EcoBank} from "../src/Ecosystem.sol";
import {Diamond, CounterFacet, RegistryFacet, LoupeFacet, FacetCut} from "../src/Diamond.sol";
import {ChildCounter, MiniFactory} from "../src/Factory.sol";
import {EnduranceMarket, IEndERC721} from "../src/Market.sol";
import {EnduranceStaking, IERC20Min} from "../src/Staking.sol";
import {Pinger, Workbench, BatchExecutor} from "../src/Batch.sol";

// Proves every endurance workload op is REVERT-SAFE under the harness's guard model.
contract EnduranceTest is Test {
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    // -------------------- tokens --------------------
    function test_ERC20_mint_transfer_approve() public {
        EndERC20 t = new EndERC20("Tok A", "TKA");
        t.mint(alice, 1e24);
        assertEq(t.balanceOf(alice), 1e24);
        vm.prank(alice);
        t.approve(bob, type(uint256).max);
        vm.prank(alice);
        t.transfer(bob, 1);
        assertEq(t.balanceOf(bob), 1);
        vm.prank(bob);
        t.transferFrom(alice, bob, 5); // max allowance path
        assertEq(t.balanceOf(bob), 6);
    }

    function test_ERC721_mint_transfer() public {
        EndERC721 n = new EndERC721("NFT", "NFT");
        n.mint(alice, 42);
        assertEq(n.ownerOf(42), alice);
        vm.prank(alice);
        n.transferFrom(alice, bob, 42);
        assertEq(n.ownerOf(42), bob);
    }

    function test_ERC1155_mint_transfer() public {
        EndERC1155 m = new EndERC1155();
        m.mint(alice, 7, 1000);
        assertEq(m.balanceOf(7, alice), 1000);
        vm.prank(alice);
        m.safeTransferFrom(alice, bob, 7, 10, "");
        assertEq(m.balanceOf(7, bob), 10);
    }

    // -------------------- multi-contract A->B->C --------------------
    function test_Ecosystem_multiHop_deposit_and_withdraw() public {
        EcoRegistry reg = new EcoRegistry();
        EcoToken tok = new EcoToken(reg);
        reg.setToken(address(tok));
        EcoBank bank = new EcoBank(tok);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        bank.deposit{value: 1e9}();
        // multi-hop effects: bank balance, reward token minted, registry bumped
        assertEq(bank.balances(alice), 1e9);
        assertEq(tok.balanceOf(alice), 1e9 * 1000);
        assertEq(reg.actions(alice), 1);
        assertEq(reg.totalActions(), 1);

        // guarded withdraw never exceeds deposited
        vm.prank(alice);
        bank.withdraw(4e8);
        assertEq(bank.balances(alice), 6e8);
    }

    // -------------------- diamond (EIP-2535) --------------------
    function _deployDiamond() internal returns (Diamond d, CounterFacet c, RegistryFacet r, LoupeFacet l) {
        c = new CounterFacet();
        r = new RegistryFacet();
        l = new LoupeFacet();
        FacetCut[] memory cuts = new FacetCut[](3);
        bytes4[] memory cs = new bytes4[](2);
        cs[0] = CounterFacet.increment.selector; cs[1] = CounterFacet.counter.selector;
        cuts[0] = FacetCut(address(c), cs);
        bytes4[] memory rs = new bytes4[](4);
        rs[0] = RegistryFacet.setEntry.selector; rs[1] = RegistryFacet.entryOf.selector;
        rs[2] = RegistryFacet.pingsOf.selector; rs[3] = RegistryFacet.totalPings.selector;
        cuts[1] = FacetCut(address(r), rs);
        bytes4[] memory ls = new bytes4[](3);
        ls[0] = LoupeFacet.facetForSelector.selector; ls[1] = LoupeFacet.allSelectors.selector;
        ls[2] = LoupeFacet.diamondOwner.selector;
        cuts[2] = FacetCut(address(l), ls);
        d = new Diamond(cuts, address(this));
    }

    function test_Diamond_routesToFacets() public {
        (Diamond d, , , ) = _deployDiamond();
        CounterFacet cf = CounterFacet(address(d));
        cf.increment(); cf.increment();
        assertEq(cf.counter(), 2);

        RegistryFacet rf = RegistryFacet(address(d));
        vm.prank(alice);
        rf.setEntry(99);
        assertEq(rf.entryOf(alice), 99);
        assertEq(rf.totalPings(), 1);

        LoupeFacet lf = LoupeFacet(address(d));
        assertEq(lf.diamondOwner(), address(this));
        assertTrue(lf.facetForSelector(CounterFacet.increment.selector) != address(0));
        assertEq(lf.allSelectors().length, 9);
    }

    // -------------------- factory + deployed-child call --------------------
    function test_Factory_create2_predict_and_call() public {
        MiniFactory f = new MiniFactory();
        bytes32 initHash = f.childInitCodeHash();
        uint256 salt = 123456789;
        address predicted = vm.computeCreate2Address(bytes32(salt), initHash, address(f));
        address child = f.createChild(salt);
        assertEq(child, predicted, "CREATE2 address must be predictable client-side");
        ChildCounter(child).bump();
        ChildCounter(child).bump();
        assertEq(ChildCounter(child).value(), 2);
    }

    function test_EOA_deployed_child_call() public {
        ChildCounter c = new ChildCounter();
        c.bump();
        c.setValue(5);
        assertEq(c.value(), 5);
    }

    // -------------------- marketplace with escrow --------------------
    function test_Market_list_and_buy_escrow() public {
        EndERC721 n = new EndERC721("MNFT", "MNFT");
        EnduranceMarket mkt = new EnduranceMarket(IEndERC721(address(n)));
        uint256 id = 1001;
        n.mint(alice, id);
        vm.prank(alice);
        n.setApprovalForAll(address(mkt), true);
        vm.prank(alice);
        mkt.list(id, 1e9);
        assertEq(n.ownerOf(id), address(mkt)); // escrowed

        vm.deal(bob, 1 ether);
        uint256 sellerBefore = alice.balance;
        vm.prank(bob);
        mkt.buy{value: 1e9}(id);
        assertEq(n.ownerOf(id), bob);
        assertEq(alice.balance, sellerBefore + 1e9);
        (, , bool active) = mkt.listings(id);
        assertFalse(active);
    }

    // -------------------- staking --------------------
    function test_Staking_deposit_and_withdraw() public {
        EndERC20 t = new EndERC20("Stake Tok", "STK");
        EnduranceStaking s = new EnduranceStaking(IERC20Min(address(t)));
        t.mint(alice, 1e24);
        vm.prank(alice);
        t.approve(address(s), type(uint256).max);
        vm.prank(alice);
        s.stake(1e20);
        assertEq(s.staked(alice), 1e20);
        vm.prank(alice);
        s.withdraw(4e19);
        assertEq(s.staked(alice), 6e19);
        assertEq(t.balanceOf(alice), 1e24 - 6e19);
    }

    // -------------------- batched multicall + workbench --------------------
    function test_Batch_pingMany_and_aggregate() public {
        Pinger p = new Pinger();
        BatchExecutor b = new BatchExecutor();
        b.pingMany(address(p), 10);
        assertEq(p.total(), 10);

        address[] memory targets = new address[](3);
        bytes[] memory data = new bytes[](3);
        for (uint256 i; i < 3; i++) { targets[i] = address(p); data[i] = abi.encodeCall(Pinger.ping, ()); }
        b.aggregate(targets, data);
        assertEq(p.total(), 13);
    }

    function test_Workbench_set_and_loop() public {
        Workbench w = new Workbench();
        w.set(5, 99);
        assertEq(w.store(5), 99);
        w.loop(50);
        assertEq(w.counter(), 2);
    }
}
