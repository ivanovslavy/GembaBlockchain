# Endurance test result — 72h run 2026-07-07 → 2026-07-10

First full **72-hour** endurance/soak of GembaBlockchain testnet (EVM chainId **821207**),
run from the Raspberry Pi (`84.242.164.248`) against the public DNS RPCs
(`rpc1/2/3.gembascan.io`) — validators never touched. Launched via
`endurance/run-72h.sh` (2× wallet funding vs the 24h run).

- **runId:** `ENDURANCE-2026-07-07T20-06-48-438Z`
- **Window:** 2026-07-07 20:06:48Z → 2026-07-10 20:11:52Z (**72h 05m**, incl. drain)
- **Profile:** ENDURANCE — 100 wallets, 4 TPS steady (5-min ramp), concurrency 20, 3 RPCs
- **Funding:** `FUND_PER_WALLET=30` GMB
- **Process:** completed normally (not killed / no abort)

## Result

| metric | value |
|---|---|
| submitted | **1,037,270** |
| mined | **1,037,232** (**99.996 %**) |
| failedSubmit | **0** |
| reverted | 5,766 (**5,762 = `nativeRemoveLiq`** — benign concurrency race, see below) |
| timedOut | 38 — all auto-**rebroadcast** |
| softSubmit (benign) | 46 (nonce 40, coalesce 6) |
| pendingAtEnd / inflight | 0 / 0 |
| latency | p50 **2,428 ms** · p95 **3,656 ms** · p99 **4,003 ms** |
| minedTps | 4.8 |

**Zero failed submits** over 1.04M txs across three full days. minedPct 99.996%.

## Day-over-day: no drift

Throughput and latency are flat from day 1 to day 3 — no memory-leak / degradation signature.

| window | mined/24h | mined TPS | p50 | p95 | p99 (avg) |
|---|---|---|---|---|---|
| Day 1 | 345,117 | 3.99 | 2,456 ms | 3,730 ms | 4,153 ms |
| Day 2 | 345,578 | 4.00 | 2,369 ms | 3,608 ms | 3,997 ms |
| Day 3 | 345,291 | 4.00 | 2,388 ms | 3,630 ms | 5,010 ms |

## The reverts are a stress-harness artifact, not a chain fault

5,762 of 5,766 reverts (99.9%) are a single op — `nativeRemoveLiq` — a benign race: 100
wallets concurrently pull liquidity from the **same** native pool, so `removeLiquidity`
often hits an already-drained position and reverts. Proof it is not a contract bug: the
end-of-run cleanup drained the pool cleanly to dust (`nativePool → 67335472 wei`). All
other op types show only 2–8 reverts each over 72h.

## One ~3-min blemish (07-10 12:42–12:45 UTC) — network, not consensus

The load generator's mined-rate briefly read 0 and its in-flight buffer piled to 83,
producing one 73s p99 tail. Validator logs (val0 `13.140.139.82`, unit `gembad-val`)
prove the **chain never missed a block or a consensus round** through the whole window:
heights advanced continuously every ~2s, `round=0` throughout. It was a transient
Pi↔RPC (Cloudflare) connectivity blip — the Pi stopped confirming/submitting, so blocks
went empty (`txs=0`) while still being produced on schedule, then fully recovered. p50
stayed flat (~2.4s) the entire time; only the tail was affected.

## Workload mix

69 distinct op types exercised (native, ERC20/721/1155, DEX add/remove/swap, WGMB
wrap/unwrap, staking, vaults, marketplace/auctions/royalties, permit/voucher, governance,
factory/clone deploys, batch/multicall, deep call chains). Top by count (proportional):
`nativeTransfer`, `dexSwap`, `erc20Transfer`, `nftMint`, `mktMint`, `nftTransfer`,
`erc20Mint`, `diamondBump`.

## Funds (fixed-supply invariant held)

Auto-cleanup at end: **recovered 27.82 GMB** from locked contracts (nativePool 11.51 →
dust, WGMB 16.31 → dust), workers drained to founder. Founder native
4,754,054.15 → 4,756,426.18 GMB (**net Δ +2,372.03 GMB, incl. gas paid**). No GMB burned.

## Gas economics (basis for scaling load)

avg **86,418 gas/tx**, effective price **7 gwei** (base 5 gwei pinned + 2 gwei tip; never
rose — blocks never filled). Total gas ≈ **627 GMB** for the run → **~6.3 GMB/wallet/72h**
at 4 TPS. Implication for a 5× run: ~31 GMB/wallet expected (≤67 worst-case if fees climb
to the 15 gwei maxFee cap), so `FUND_PER_WALLET=30` is **not** enough at 5× — see the 5×
run (`run-72h-5x.sh`, `FUND_PER_WALLET=100`).

## Verdict

Pass. The chain sustains **72h** of continuous, realistic load over the rate-limited
public RPCs from a single low-power box, with no throughput or latency drift and no
consensus disruption. Follow-up: a **5× throughput** 72h run (20 TPS, concurrency 100)
launched 2026-07-13 via `endurance/run-72h-5x.sh`.
