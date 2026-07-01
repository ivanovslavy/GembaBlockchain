# GembaBlockchain — 24-hour endurance / soak test (2026-06-29 → 06-30)

First full **24-hour endurance (soak)** run against the live public testnet
(`gemba-testnet-1`, EVM chainId 821207). Where the [stress test](./stress-test-2026-06-07.md)
found the *throughput ceiling*, this run tests **sustained reliability**: diverse EVM traffic,
continuously, for a full day.

Harness: [`endurance/`](../endurance) (Node + ethers, 16 deployed contracts, ~70 realistic
operation types, JSONL logging + summary). Runner: the operator box (`nft-ticket-server`,
84.242.164.248) against the public RPC. 100 wallets, 20 s settle window.
Run `ENDURANCE-2026-06-29T19-26-14-352Z`, finished `2026-06-30T19:31:18Z` (**24 h 5 m**).

## Headline result — flawless

- **346,322 transactions submitted → 346,322 mined = 100.0 %** over 24 hours.
- **0 failed submits · 0 reverted · 0 timed out · 0 pending at the end** — clean finish, not a single stuck tx.
- Hard errors: **none** (`errors: {}`). Rebroadcasts: 0.
- **Inclusion latency (submit → mined): p50 2.38 s · p95 3.68 s · p99 4.09 s** — inside a single ~5 s block, all day long.
- Only **143 soft/transient events** (31 nonce races + 112 coalesce), every one auto-recovered (mined == submitted; `softErrors` only).
- Soak pacing held ~6 tx/s mined — this run measures **reliability under continuous load**, not peak TPS (the ceiling ≈112 TPS is in the stress-test doc).

## Transaction mix — 70 op types

346,322 transactions across **70 distinct EVM operation types** (a weighted realistic mix; every
op is state-guarded so nothing reverts). Top of the distribution:

| op type | count | | op type | count |
|---|---:|---|---|---:|
| nativeTransfer | 19,449 | | disperseMany | 5,952 |
| erc20Transfer | 13,774 | | batchMulticall | 5,940 |
| dexSwap | 13,756 | | workbenchSet | 5,933 |
| mktMint | 7,912 | | stakeDeposit | 5,923 |
| nftMint | 7,761 | | erc20Mint | 5,907 |
| nativeSwapIn | 6,000 | | erc1155Mint | 5,905 |
| deepChainRun | 5,963 | | erc1155Transfer / vaultDeposit | ~5,9k each |

The remaining ~56 types fill the long tail: DEX add/remove-liquidity, NFT transfer/stake,
ERC-4626 vault deposit/mint/withdraw/redeem, plain + time-based reward staking, governance
propose/vote/queue/execute, English/Dutch auctions, clone/factory deploys, deep 5-hop chains +
reentrant callbacks, EIP-2612 permits, rebasing, disperse-to-many, events-heavy, etc. `forge
test` proves every op family is revert-safe (23 passed / 0 failed).

## Gas & cost

- **Total gas used: 29,966,740,920** over 37,473 tx-bearing blocks (**avg 86,528 gas/tx**).
- **Base fee stayed pinned at the 5 gwei floor for the entire run** — it never rose, i.e. the load
  never congested the chain (blocks stayed far from the 100 M gas limit). Effective price = 5 gwei
  base + 2 gwei priority = **7 gwei**.
- **Total transaction fee ≈ 210 GMB** (29.97 B gas × 7 gwei effective) — in EVM the *fee is the
  gas cost*; there is no separate fee. Split (EIP-1559): **≈150 GMB base fee** (5 gwei) +
  **≈60 GMB priority tip** (2 gwei, to validators). All **valueless test GMB.**

## Funding & cleanup

- Funded **100 worker wallets** (top-up to a 15 GMB target each ⇒ **≈1,500 GMB**), paid by the
  **testnet founder** key — valueless test GMB.
- After the run the pool holds **≈1,270 GMB** (avg 12.7/wallet); the ~230 GMB delta = the ~210 GMB
  of gas + test GMB parked inside wrap/DEX/liquidity contracts by the workload.
- **Leftover NOT yet returned to the founder** — the `scripts/drain-to-founder.mjs` sweep (worker
  GMB → founder) has not been run for this run. (Once run, the ~1,270 GMB test GMB returns to the
  founder key.)

## Verdict

The chain carried continuous, diverse EVM load for a full day with **zero lost or failed
transactions** and sub-block-time inclusion latency throughout — no latency creep, no
consensus stalls, no mempool build-up, no stuck transactions at the end. This clears the
**sustained-load reliability** bar for mainnet.

> Public launch is still gated by the remaining `CLAUDE.md` §16 hard blockers (upstream audit +
> security-budget tail). This test is **one readiness milestone met**, not the whole gate.

Raw logs are large and not committed (`endurance/logs/` is git-ignored) — they live on the
runner at `endurance/logs/ENDURANCE-2026-06-29T19-26-14-352Z/` (`tx.jsonl` 49 MB,
`blocks.jsonl`, `metrics.jsonl`). The machine-readable summary:

```json
{
  "runId": "ENDURANCE-2026-06-29T19-26-14-352Z",
  "profile": "ENDURANCE",
  "finishedAt": "2026-06-30T19:31:18.800Z",
  "wallets": 100,
  "settleMs": 20000,
  "submitted": 346322,
  "mined": 346322,
  "failedSubmit": 0,
  "softSubmit": 143,
  "reverted": 0,
  "timedOut": 0,
  "inflight": 0,
  "submitTps": 3.2,
  "minedTps": 6,
  "p50": 2379,
  "p95": 3677,
  "p99": 4093,
  "errors": {},
  "softErrors": { "nonce": 31, "coalesce": 112 },
  "minedPct": 100,
  "rebroadcasts": 0,
  "pendingAtEnd": 0
}
```
