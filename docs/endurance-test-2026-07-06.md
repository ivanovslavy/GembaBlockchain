# Endurance test result — 24h run 2026-07-05 → 2026-07-06

Second full 24-hour endurance/soak of GembaBlockchain testnet (EVM chainId **821207**),
run from the Raspberry Pi (`84.242.164.248`) against the public DNS RPCs
(`rpc1/2/3.gembascan.io`) — validators never touched. Reproduces the 2026-07-01 milestone.

- **runId:** `ENDURANCE-2026-07-05T09-46-54-218Z`
- **Window:** 2026-07-05 09:46:54Z → 2026-07-06 09:52:00Z (**24h 05m**, incl. drain)
- **Profile:** ENDURANCE — 100 wallets, 4 TPS steady (5-min ramp), concurrency 20, 3 RPCs
- **Process:** completed normally (not killed / no abort)

## Result

| metric | value |
|---|---|
| submitted | **346,312** |
| mined | **346,299** (**99.996 %**) |
| **reverted** | **0** |
| **failedSubmit** | **0** |
| timedOut | 13 — all 13 auto-**rebroadcast** and recovered |
| softSubmit (benign) | 50 (nonce 40, coalesce 10) |
| pendingAtEnd / inflight | 0 / 0 |
| latency | p50 **2,508 ms** · p95 **3,790 ms** · p99 **4,178 ms** (block time ≈ 5.2 s) |
| minedTps | 2.4 |

**Zero reverts, zero failed submits** over ~346k txs across a full day. The only 13
timeouts were transparently rebroadcast and mined — net 0 lost.

## Workload mix

70 distinct op types exercised (native, ERC20/721/1155, DEX add/remove/swap, WGMB
wrap/unwrap, staking, vaults, marketplace/auctions/royalties, permit/voucher, governance
propose→vote→queue→execute, factory/clone deploys, batch/multicall, deep call chains).
Top by count: `nativeTransfer` 19,547 · `dexSwap` 13,699 · `erc20Transfer` 13,620 ·
`nftMint` 7,862 · `mktMint` 7,695 · `auctionMint` 6,000 · `feeSwap` 5,932.

## Funds (fixed-supply invariant held)

Auto-cleanup at end: **recovered 115.38 GMB** from locked contracts
(nativePool 109.70 → dust, WGMB 5.67 → dust), workers drained to founder.
Founder native 4,755,669.08 → 4,757,054.33 GMB (**net Δ +1,385.26 GMB, incl. gas paid**).
No GMB burned.

## Verdict

Pass. The chain sustains 24h of continuous, realistic, revert-free load driven entirely
over the rate-limited public RPCs from a single low-power box. Follow-up: a **72h** run
(2× wallet funding) launched via `endurance/run-72h.sh`.
