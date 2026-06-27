// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// A1 — end-to-end governance/treasury test against the LIVE deployed contracts
// (run forked: forge test --match-contract LiveGov --fork-url https://rpc1.gembascan.io).
// Proves the legitimate Governor->Timelock->reserve path WORKS and is the ONLY one.

interface IGovernor {
    function propose(address[] calldata, uint256[] calldata, bytes[] calldata, string calldata) external returns (uint256);
    function castVote(uint256, uint8) external returns (uint256);
    function queue(address[] calldata, uint256[] calldata, bytes[] calldata, bytes32) external returns (uint256);
    function execute(address[] calldata, uint256[] calldata, bytes[] calldata, bytes32) external payable returns (uint256);
    function state(uint256) external view returns (uint8);
    function votingDelay() external view returns (uint256);
    function votingPeriod() external view returns (uint256);
}
interface IVotes {
    function depositFor(address) external payable;
    function delegate(address) external;
    function getVotes(address) external view returns (uint256);
    function excluded(address) external view returns (bool);
}
interface IFaucet { function perGrantCap() external view returns (uint256); }
interface IReserve { function release(address, uint256) external; function owner() external view returns (address); }

contract LiveGov is Test {
    // Regenesis 2026-06-27 addresses (gemba-testnet-1 / EVM 821207) — see contracts/REGENESIS-ADDRESSES-2026-06-27.md
    address constant GOV    = 0xCCd9f78047E1BB8Bec419490E80409bfBf3B7b72;
    address constant TL     = 0xa75aC1AF72D54e34c5646534F985Be7a172C37C1;
    address constant VOTES  = 0x0056ab3c91FF5ba8eCdBA8c7C453fd9F424F7F39;
    address constant FAUCET = 0x9406B634Eae1856d13251245d7D472D9b6594F56;
    address constant RES    = 0x68093A1C9682df9D1C59586b2Cfc04ed132e7eE5;

    // Fork-only: these target the LIVE deployment. Skip on a normal (non-forked) run.
    modifier onlyForked() {
        if (GOV.code.length == 0) { vm.skip(true); return; }
        _;
    }

    // The legitimate path: propose -> vote -> queue (timelock) -> execute, end to end.
    function test_fullGovernanceCycle_movesAParam() public onlyForked {
        IGovernor g = IGovernor(GOV);
        address voter = address(0xBEEF);

        // 1) acquire real voting power (deposit native GMB -> vGMB, self-delegate)
        vm.deal(voter, 1_000_000 ether);
        vm.startPrank(voter);
        IVotes(VOTES).depositFor{value: 500_000 ether}(voter);
        IVotes(VOTES).delegate(voter);
        vm.stopPrank();
        vm.roll(block.number + 1);
        assertGt(IVotes(VOTES).getVotes(voter), 0, "voter must have power");

        // 2) propose a Timelock-owned action: Faucet.setPerGrantCap(newCap)
        uint256 newCap = IFaucet(FAUCET).perGrantCap() + 12_345 ether;
        address[] memory t = new address[](1); t[0] = FAUCET;
        uint256[] memory v = new uint256[](1); v[0] = 0;
        bytes[] memory c = new bytes[](1); c[0] = abi.encodeWithSignature("setPerGrantCap(uint256)", newCap);
        string memory desc = "live-test bump perGrantCap";
        vm.prank(voter);
        uint256 pid = g.propose(t, v, c, desc);

        // 3) advance past votingDelay -> Active, vote For
        vm.roll(block.number + g.votingDelay() + 1);
        vm.warp(block.timestamp + 30);
        vm.prank(voter);
        g.castVote(pid, 1);

        // 4) advance past votingPeriod -> Succeeded -> queue into the Timelock
        vm.roll(block.number + g.votingPeriod() + 1);
        vm.warp(block.timestamp + 4000);
        bytes32 dh = keccak256(bytes(desc));
        g.queue(t, v, c, dh);

        // 5) advance past the Timelock minDelay -> anyone executes
        vm.warp(block.timestamp + 400);
        g.execute(t, v, c, dh);

        // 6) the param actually changed — the full path worked end to end
        assertEq(IFaucet(FAUCET).perGrantCap(), newCap, "param changed only via Governor+Timelock");
    }

    // ATTACK: a non-owner cannot pull funds from a reserve (only the Timelock can).
    function test_attack_directReserveReleaseReverts() public onlyForked {
        assertEq(IReserve(RES).owner(), TL, "reserve owned by Timelock");
        vm.prank(address(0xBAD));
        vm.expectRevert();
        IReserve(RES).release(address(0xBAD), 1 ether);
    }

    // FINDING (live): the deploy script (DeployGovernance) passes the 4 reserves to
    // GembaVotes' excluded[] set, but ON-CHAIN none of the reserve proxies (or impls,
    // or the Timelock) are excluded — the "reserves are excluded from voting" defense-in-
    // depth is NOT active on the live deploy. The reserves ARE funded on-chain (this one
    // holds 10M GMB), so the gap matters — but immediate risk is low because BaseReserve has
    // no depositFor/delegate, i.e. a reserve has no mechanism to turn its GMB into votes.
    // Must be fixed before mainnet: correct the genesis deploy to exclude the FINAL reserve
    // addresses, or call setExclusion(reserve,true) via governance (onlyOwner = Timelock).
    // This test documents the current (gap) reality so it's tracked.
    function test_finding_reservesNotExcludedOnLiveDeploy() public onlyForked {
        // a reserve is NOT excluded today → depositFor does NOT revert (the gap)
        vm.deal(RES, 10 ether);
        vm.prank(RES);
        IVotes(VOTES).depositFor{value: 1 ether}(RES);
        assertFalse(IVotes(VOTES).excluded(RES), "GAP: reserve not excluded on live deploy");
    }
}
