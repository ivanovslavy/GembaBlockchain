# Explorer: dedicated pruned node + indexing tuning under load

Status: **partially done (tuning applied as a stopgap) — dedicated pruned node is an open TODO.**
Origin: 2026-07-13, during the 5× endurance run (~46 tx/block, ~20 TPS).

> **Direction superseded (2026-07-13) — see `target-architecture.md`.** The chosen fix is to move
> the archive to a Hetzner cax31 (real NVMe), not to add a pruned node. The **tuning changes in
> this doc are still applied** to the current `.137` archive + `213.136.85.32` explorer and stay
> in effect until that migration.

## TL;DR

Under heavy load the GembaScan/Blockscout explorer **freezes / falls behind** because its
only data source is the **single archive node `.137`**, and that box (Contabo, ~6 cores,
"NVMe" that benchmarks like an HDD ≈ 250 MB/s vs a real Hetzner NVMe ≈ 1.6 GB/s) cannot
**both** keep the archive synced to the tip **and** serve Blockscout's heavy read load
(traces + token/contract-discovery `eth_call`s). It applies fat 5× blocks at only ~0.5
blk/s vs the chain's ~0.43 blk/s — almost no headroom, so any read load pushes it negative.

- **Durable fix (TODO):** stand up a **dedicated pruned node** on a decent separate box
  and point the explorer at it. Do this on **testnet now** and again **on mainnet launch**.
- **Stopgap (applied 2026-07-13):** raised the archive RPC timeouts + throttled Blockscout's
  fetchers so it degrades gracefully (lags ~15-18 min under 5×, no hard stall) instead of
  freezing. See "Applied changes" — **these are candidate mainnet settings.**

---

## TODO — dedicated pruned RPC node for the explorer

**Goal:** the explorer reads from its **own** node, never from a validator or the archive.

Why **pruned** (not archive): a pruned node discards old historical state, so it applies
blocks much lighter (far less disk I/O) → it keeps up with the tip with CPU/I-O to spare
for serving reads. Blockscout traces blocks **as they arrive** (recent blocks), for which a
pruned node has the state — so real-time indexing (incl. `call_tracer` internal txs) works
fine. It only cannot serve **deep-historical** trace/state (old blocks beyond its prune
window); keep the existing `.137` archive as a fallback for that (Blockscout can point deep
queries at the archive URL, real-time at the pruned node).

Target architecture:
```
validators (.82/.83/.84/.100) ─┐
                                ├─→ [NEW pruned node, own box, real NVMe] ─→ Blockscout (real-time)
archive .137 ───────────────────┘        (fallback only for deep history)
```

Checklist:
- [ ] Provision a box with **real NVMe + good single-thread CPU** (Hetzner dedicated /
      Serverbörse is both faster and cheaper than Contabo for this I/O-bound role; ~€35-60/mo).
      Contabo is fine for RAM/storage-bound roles but NOT for a node's disk I/O.
- [ ] Install `gembad` as a **pruned** full node (`pruning = "default"` or custom, NOT
      `pruning = "nothing"`), `state-sync` or snapshot to catch up, join via persistent_peers.
      Base off `docs/runbooks/node-setup.md`; it does NOT need to be a validator.
- [ ] Enable JSON-RPC with the debug/tracing namespace and the timeout settings below.
- [ ] Repoint Blockscout `ETHEREUM_JSONRPC_HTTP_URL` (+ `TRACE_URL`) at the new node
      (over the existing autossh-tunnel pattern or a private link). Optionally keep the
      `.137` archive as a secondary/archive URL for deep history.
- [ ] Once stable, the Blockscout throttles below can be **relaxed** (the pruned node has
      headroom the archive never did).
- [ ] **Mainnet:** do the same from day one — dedicated pruned explorer node on Hetzner.

---

## Applied changes 2026-07-13 (stopgap; candidate mainnet settings)

All files backed up in place as `*.bak-<UTC-timestamp>` before editing.

### A. Archive node `.137` — raise RPC timeouts
File: `~/.gembad-archive/config/app.toml`, `[json-rpc]` section. Restart: `systemctl restart gembad-archive`.

| key | was | now | why |
|---|---|---|---|
| `evm-timeout` | `5s` | `60s` | tracing a fat block (`debug_traceBlockByNumber` + `call_tracer`) takes >5s under load; at 5s the node returned `-32002 "request timed out"` and Blockscout could not index at all. 60s lets heavy traces complete. |
| `http-timeout` | `30s` | `120s` | must be ≥ evm-timeout so it doesn't cap the longer trace. |

Note: Blockscout already uses the cheap `call_tracer` (not the opcode struct-logger), so the
tracer was **not** the lever — the 5s cutoff was.

### B. Explorer `213.136.85.32` — throttle Blockscout fetchers
File: `/root/gembascan/envs/backend.env`. Recreate: `docker compose -p gembascan up -d --force-recreate --no-deps backend`.
Goal: stop Blockscout from flooding the archive with parallel reads (it hit ~18 `eth_call`/s,
each ~930 ms, mostly "execution reverted" from token/contract discovery) which **starved the
archive's own consensus sync to a full stall (0 commits)**. Gentler fetchers leave the box CPU/I-O to stay synced.

| env | Blockscout default | set to |
|---|---|---|
| `INDEXER_INTERNAL_TRANSACTIONS_BATCH_SIZE` | 10 | **5** |
| `INDEXER_INTERNAL_TRANSACTIONS_CONCURRENCY` | 4 | **3** |
| `INDEXER_CATCHUP_BLOCKS_CONCURRENCY` | 10 | **2** |
| `INDEXER_CATCHUP_BLOCKS_BATCH_SIZE` | 10 | **5** |
| `INDEXER_TOKEN_BALANCES_CONCURRENCY` | 10 | **2** |
| `INDEXER_COIN_BALANCES_BATCH_SIZE` | 500 | **100** |
| `INDEXER_RECEIPTS_CONCURRENCY` | 10 | **5** |

Result: `eth_call` load fell (~337→~113 per 15 s), the archive stopped stalling and lags
**gracefully** (~15-18 min behind live under 5×, explorer shows real data), and fully catches
up when the load drops. On a proper pruned node these can be relaxed toward defaults.

### C. (related, same day) docker log rotation on the explorer box
The `gembascan-db-1` + `gembascan-backend-1` json-file logs had ballooned to **53 GB** (disk 83%)
because their containers predate the `daemon.json` cap and inherited no limit. Fix: truncated
the live logs (`truncate -s 0`, no restart) and added explicit `logging: {max-size:100m, max-file:3}`
to `db` + `backend` in `/root/gembascan/docker-compose.yml` (recreated). **Bake the same
`logging:` cap into every service in the mainnet explorer compose from the start.**

## Recovery note

If the archive ever hard-stalls (0 commits while behind, RPC alive): `systemctl restart
gembad-archive` re-enters block-sync. If Blockscout's read flood is what starved it,
`docker stop gembascan-backend-1` first, let the node catch up, then start the backend.

## Root cause in one line

Hardware: Contabo "NVMe" ≈ HDD-speed disk I/O; an archive node applying fat 5× blocks **and**
serving the explorer's trace/eth_call load exceeds it. Real fix = right hardware (Hetzner NVMe)
+ a dedicated pruned node so sync and serving don't fight. See topology in `docs/SERVER-TOPOLOGY.md`.
