# Stress run — post-regenesis B→C (2026-06-27/28)

First full overnight stress run after the 2026-06-27 regenesis. B (2h) → C (4h), chained
(`overnight-BC.sh`), driven from the .83 node's localhost RPC (raw consensus ceiling).

## Result — the chain handled it cleanly

| | Profile B (2h: ramp→hold 26→spike 48→cooldown) | Profile C (4h soak @13 tps) |
|---|---|---|
| Submitted / Mined OK | 180,200 / 156,834 | 185,970 / **185,860 (99.94%)** |
| Reverted | 18,037 *(by design)* | **0** |
| FailedSubmit / TimedOut | 6,036 / 5,272 | **42 / 110** |
| Peak mined TPS | 62.6 | 36.4 |
| Latency p50 / p95 | 3.06s / 89s | **2.6s / 3.78s** |
| Block fill (of 100M gas) | 6% | ~0% |
| Base fee | 5.00 → **5.00 gwei (flat)** | 5.00 → 5.00 gwei |
| Block time avg/max | 2.40s / 7.27s | 2.34s / 6.98s |

- **Supply invariant held: 100,000,000 GMB unchanged** end-to-end (§3.1).
- All 4 validators stayed **BONDED, none jailed/tombstoned** during the run; all nodes in sync.
  (One validator sits at 9913 GMB from a downtime slash on **2026-06-26** — before this run, not
  caused by it; the slashed coins went to the faucet, not burned → supply still 100M.)
- mempool peak **0**, base fee never left the 5-gwei floor → the chain had huge headroom; the
  bottleneck was the single load-generator box (nonce races + latency spike at the 48-tps spike),
  not the chain or the validators.
- Gas spent over the whole night (B+C, ~370k txs): **~146.5 GMB**.

## Issues found + fixed in the harness (post-regenesis drift)

1. **Funder key in `.env` was the compromised `0x40a0cb1C` (pentest P-1) and held 0 GMB** after
   regenesis → generated a fresh funder, funded from the founder.
2. **`npm run fund` (Disperse contract) is broken** — the pre-regenesis `Disperse` address is **dead
   (no code)**, so `disperse()` with `value` just sent GMB to a codeless address (1500 GMB stuck,
   unrecoverable). → Added **`direct-fund.mjs`** (funder → each wallet directly, no Disperse).
3. **`MAX_FEE_GWEI=3` was below the post-regenesis `5 gwei` base-fee floor** → all txs underpriced
   and rejected. → Bumped to 15; `run.js` already uses a dynamic 2×base+tip fee.
4. **The whole deployed contract suite was dead** (pre-regenesis addresses) → re-ran `npm run deploy`.

## New harness scripts (this run)
- `direct-fund.mjs` — fund worker wallets directly from the funder (bypasses the dead Disperse).
- `drain-to-founder.mjs` — return all worker + funder GMB to the founder; prints the gas-spent report.
- `overnight-BC.sh` — run B then C back-to-back (detached), for an unattended overnight run.

Reports: `logs/B-2026-06-27T22-06-43-126Z/report.md`, `logs/C-2026-06-28T00-08-16-520Z/report.md`.
