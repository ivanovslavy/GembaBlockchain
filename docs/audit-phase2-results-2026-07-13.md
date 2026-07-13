# Audit Phase 2 — dynamic validation results, 2026-07-13

Phase 2 exercises the findings/fixes on a **throwaway isolated devnet** (`gemba-1` / EVM 821206,
`security/devnet/up.sh`, 4 nodes, this box's `gembad d8a454f-dirty`) plus **read-only/bounded
probes against the live testnet** — never destructive against the live chain (the 5× endurance run
was still in progress).

## Real attacks run — all passed

### RPC hardening (LIVE rpc1/2/3, read-only) — PASS
`security/track3-rpc-infra/rpc-expose-probe.sh` against the public RPCs: every dangerous namespace
is blocked — `admin_nodeInfo`, `personal_listAccounts`, `txpool_content`, `miner_setEtherbase`,
`debug_traceBlockByNumber` all return `-32601 does not exist/is not available`. (The P-2 pentest fix
holds.) Residual: `web3_clientVersion` still returns the build string — a minor info leak (P-3),
not fixed here.

### Consensus — downtime slash → faucet (devnet) — 4/4 PASS
Stopped a validator until jailed (~34s), then asserted the §5.6/§3.1 invariants on a live chain:
validator jailed + slashed (10,000 → 9,900 GMB, 1%), **total supply UNCHANGED** (slash not burned),
and the slashed stake **redirected to the faucet** (+100 GMB) by `x/slashfunds`. Empirically
re-confirms the P-4 fix (no burn) under real slashing.

### Consensus — double-sign → tombstone (devnet) — 5/5 PASS
Ran a duplicate instance with the same consensus key to force equivocation. Result: evidence
detected (~32s), validator **tombstoned** (permanent), stake slashed (10,000 → 9,500 GMB, 5%),
**total supply UNCHANGED**, slashed stake **redirected to the faucet** (+500 GMB). Fixed-supply +
slashfunds hold under a double-sign, not just downtime.

### H1 — empirically confirmed on the devnet genesis
`gembad query valgate params` on the devnet returns ONLY `min_self_bond` — the devnet genesis omits
`max_self_bond` / `max_daily_bond_increase`, exactly the omission H1 fixes (the shipped genesis
leaves the caps off; only the runtime GetParams re-default keeps the Cosmos-path daily cap at 50).

## Fixes validated at unit level (Phase 1 commits) — reconfirmed green
Full suites re-run after all fixes: chain modules pass; contracts **181 tests, 0 failed**. Includes
the new M2/M4 round-trip + budget tests and the updated M3 two-tier tests (reserve release + UUPS
upgrade now assert Critical; ordinary call stays Standard).

## Still outstanding — M1 (the one deferred fix)
**M1 (precompile daily-bond-cap bypass)** was NOT force-fixed in-tree, deliberately. Its correct fix
is out-of-tree wiring — wrap the staking `MsgServer` the EVM staking precompile calls so
`Delegate`/`BeginRedelegate` enforce `CheckAndRecordDailyBond` before delegating (hooks can't: they
lack the amount and can't cleanly distinguish the creation self-bond). That change requires a full
`build-gembad.sh` (fetch cosmos/evm v0.7.0 + apply the wiring patch + build) and an EVM-RPC devnet to
drive a precompile `delegate` exceeding 50 GMB/day and assert rejection. It is the next focused task
(design in `mainnet-launch-hardening.md` §C) — not rushed at the tail of the audit, since a botched
consensus-wiring change is worse than a documented Medium rate-limit gap. The devnet's EVM JSON-RPC
was not enabled by the default `up.sh`, so the precompile PoC also needs a node started with
`--json-rpc.enable`.

## Not run against live (by policy)
Bounded live contract-drain attacks (`collector-attack.mjs`, funded from the founder key on the Pi)
were left for a window when the 5× endurance run is not consuming the live chain; the prior
`live-deployment-security-2026-06-26` audit already ran 5 drain attacks (all reverted). Heavy RPC
DoS / mempool flooding stays devnet-only.

## Net Phase-2 verdict
The fixed-supply / no-burn / slashfunds core and RPC hardening are **empirically solid under real
slashing and equivocation on a live devnet**. The Phase-1 code fixes pass their suites. The single
remaining engineering task is the M1 precompile wrapper (build + devnet EVM PoC).
