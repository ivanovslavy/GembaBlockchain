# GembaBlockchain — Stress test (2026-06-07)

First load test of the live public testnet (`gemba-testnet-1`, EVM chainId 821207).
Harness: [`stress/`](../stress) (Node + ethers v6 load generator, diverse EVM workloads,
JSONL logging + analysis). Generator ran **on validator node .83** (13.140.139.83) against
its **local EVM RPC** (txs gossip via CometBFT P2P → all 4 validators do consensus; one node
is just the entry point). 300 fresh wallets, funded 5 GMB each from `tnfaucet`. Block time
≈ 5.2–5.4 s.

## Headline result
- **Sustained ceiling ≈ 112 TPS mined** (knee at ~150 TPS submit), 88.6% mined, **max 764
  EVM tx/block**, blocks stable at **avg 5.4 s (max gap 8 s)** throughout the push.
- **Not gas-limited** — blocks were only ~5–27% full by gas (limit 100 M). The chain core is
  strong; the throughput lever is **block time**, not block size.
- Calibration: an early conservative read (~44 TPS, or ~12.8 with cap=4) was a *harness*
  artifact; raising the per-wallet in-flight window (cap=8) + a more aggressive ramp revealed
  the real ~112 TPS.

## Validator-machine load during the test (key finding)
| node | role | loadavg (4 cores) | mem | swap | gembad CPU |
|---|---|---|---|---|---|
| **.84** | validator only | **0.26** | 2.2 GB | 0 | ~7.6% |
| **.82** | validator **+ archive + Blockscout** | **5.4** | 7.2 GB (full) | 1.8 GB | 100% spikes |
| .83 | validator + the load generator | high (generator) | — | — | — |
| node2 | validator (LAN/NAT) | not reachable from CI | — | — | — |

➡️ **A pure validator (.84) sat at ~0.2 load while the network did 112 TPS** — consensus is
cheap. All the strain was on boxes doing *extra* duty (.82 explorer, .83 generator).

## What "broke" — the explorer, never the chain
Under 112 TPS / 764-tx blocks, **Blockscout (Postgres + Elixir) on .82 saturated CPU→100% and
pushed swap to 93%**, so the explorer UI froze on a block ~minutes stale. **The chain never
halted**: all validators stayed `catching_up=false`, the .82 validator never fell behind, no
OOM. It recovered fully the moment load stopped (indexer caught back up to the tip).

## Errors (all via the single .83 RPC entry point)
submit 3268 · revert 945 (mostly the intentional `revertOp`) · timeout 2512 (~10%, at the ceiling).

Submit-error reasons:
- **~1900 "replacement fee too low"** — harness nonce-resync re-sending a nonce at equal gas.
- **491 "insufficient gas for floor data gas cost"** — the `bigCalldata` workload: gas limit
  1.3 M < the protocol's calldata-gas floor (EIP-7623) of ~2.02 M for ~50 KB calldata.
- **365 "nonce"** — gaps at peak.

Note: errors are RPC-ingestion rejections at .83 (the only RPC used) — not attributable to a
specific validator. For per-validator attribution, point the generator at all nodes' RPCs.

## Findings & recommendations (ranked)
1. **[Infra — mainnet-critical] Do not co-host the explorer with a validator.** Blockscout's
   indexer + archive node are the heavy components; under load they risk OOM-killing the
   co-located validator. Isolate explorer + archive onto their own (larger-RAM) box; keep
   validator machines lean (validator only — .84 proved it idles at 112 TPS). *Interim done:*
   +2 GB swap on .82 (now 4 GB).
2. **[Throughput] The lever is block time** (`timeout_commit ≈ 5 s`). 112 TPS at modest gas
   fill → lowering `timeout_commit` toward ~2 s should raise TPS ~linearly. (Matches the
   existing TODO: "block time 5–6 s vs 2 s target".)
3. **[Chain behavior to document for dapp devs]**
   - Cosmos EVM returns a **tx hash for a future-nonce tx with no submit error**; it never
     mines until the gap fills. Tooling must bound in-flight per account / manage nonces.
   - **EIP-7623 calldata floor:** large-calldata txs must carry gas ≥ the calldata floor or
     are rejected ("insufficient gas for floor data gas cost").
4. **[Harness] applied:** bounded per-wallet in-flight nonce window + resync; `dexRemoveLiq`
   gated to wallets that added liquidity (was Panic 0x11 underflow). *Remaining polish:* raise
   `bigCalldata` gas to ≥ 2.1 M (or shrink calldata); bump gas price on nonce-resync resend to
   avoid "replacement fee too low"; WS receipt subscription for sharper latency.

## Cleanup performed
- **Returned 1495 GMB** from the 300 wallets to `tnfaucet` (back to ~1,999,395 GMB; the whole
  test cost ≈ 5 GMB in gas).
- **Reverted .83 `app.toml`**: JSON-RPC `enable=false` + `enable-indexer=false`, validator
  restarted and signing (`catching_up=false`), :8545 closed. (Backups: `app.toml.bak.*`.)
- **Added 2 GB swap on .82** (`/swapfile2`, persistent via fstab; total swap 4 GB).

## Open (owner)
- Decide where to relocate the explorer (the single heaviest component) for mainnet.

---

# Soak test (profile C) — 2026-06-08

Run from the RPi (`192.168.100.11`) **directly against the validators' RPCs** (node2 LAN +
.83/.84 raw :8545), `SOAK_TPS=20`, ~4 hours, with a **rich routine-tx mix** (no adversarial ops).

## Result
| | |
|---|---|
| Submitted | **284,649** |
| Mined OK | **281,950 (99.05%)** |
| Reverted | **0** |
| Failed submit | **0** |
| Timed out | 2,699 (0.95%) |
| Latency | p50 3.9s · p95 6.3s · p99 6.8s (~1 block) — **stable for the full 4 h** |
| Sustained TPS | ~20, no degradation |

## Workload diversity (all 0-revert)
native transfer 68k · ERC20 transfer 51k · **NFT mint 34k** · ERC1155 transfer 23k ·
**NFT transfer 22k** · **wrap GMB→WGMB 17k** · DEX swap 14k · ERC20 mint 14k ·
**unwrap 11k** · ERC20 approve 8.5k · ERC1155 mint 8.5k · DEX addLiquidity 5.7k · storage 5.7k.

Added a `StressNFT` (caller-chosen-id) contract so NFT *transfer* is valid (the auto-increment
StressERC721 can't be transferred reliably client-side); wrap/unwrap via the real WGMB.

## Node health after 4 h
- **Validators barely loaded:** .82/.83/.84/node2 loadavg **0.13–0.46**, none `catching_up`.
  Consensus is cheap; RPC ingestion is light. Validator data-dirs ~2.5–2.7 GB.
- **Explorer box (.137) carried the indexing:** loadavg ~5.6, RAM 7.9/12 GB (+12 GB swap),
  172 GB disk free — kept up indexing the whole soak. (Confirms: isolate explorer from validators.)

## Verdict
The chain is **rock-solid under sustained, diverse, routine load** — 282k txs, 99% mined, zero
reverts across 13 tx types, ~1-block latency with no drift, zero validator stress.

## Cleanup
1,473 GMB swept back to `tnfaucet`; .83/.84 raw RPC reverted to 127.0.0.1 + ufw rules removed
(rpc1/rpc2 keep serving via nginx) → validators "naked" again.
