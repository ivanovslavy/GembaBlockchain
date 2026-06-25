# GembaBlockchain — Stress-test harness

Load generator + diverse EVM workloads + full logging and analysis. Targets the **live
testnet directly through a node's EVM RPC** (bypassing Cloudflare/Apache). Txs gossip via
CometBFT P2P, so **all 4 validators** take part in consensus — submitting through one node
stresses the whole network. Block time ≈ **5.2s**.

> ⚠️ The public testnet hosts live apps (EduChain, GembaPass). This harness includes a
> **disk guard** (aborts if the node data dir free space drops below `DISK_MIN_FREE_GB`)
> and a **catching_up guard** (aborts if a node falls behind). Run in a quiet window.

## What it does
- Generates N fresh wallets, funds them from a faucet-seeded **funder** (saves PKs locally, gitignored).
- Deploys a contract suite: 2× ERC20, ERC721, ERC1155, Storage, GasBomb, Disperse, a self-contained AMM (StressDex).
- Drives a weighted mix: native + ERC20 transfers/approves/mint, ERC721/1155 mint+transfer,
  SSTORE/compute, contract deploys, **DEX swap / add / remove liquidity**, and **adversarial**
  ops (gas bombs, ~50KB calldata, intentional reverts).
- Pipelines txs per wallet (manual nonce, no receipt-wait) → high submit rate; a separate
  collector resolves receipts (block, status, gasUsed, latency).
- Logs everything to `logs/<runId>/` (jsonl, gzip-rotated) and produces `report.md`.

## Profiles (run separately)
| Profile | Mode | Duration | Purpose |
|--|--|--|--|
| **A** | ramp + auto-knee | ~30 min | find the TPS ceiling (warmup → +10 tps/30s until latency/errors/plateau) |
| **B** | phases | ~2 h | ramp → hold 80% of knee → 150% spike → cooldown |
| **C** | soak | ~4 h | steady moderate load — slow leaks, state growth, block-time drift |

A prints a suggested `TARGET_TPS`; set it in `.env` before B and C.

## Run (on the .83 node)
```bash
# once, locally (where Foundry is): compile + extract artifacts, then copy the dir to .83
npm run build                      # forge build → artifacts/*.json

# on .83:
cp .env.example .env               # set FUNDER_PK (seed it from the faucet first), RPC_URLS, NODE_DATA_DIR
npm install
npm run gen-wallets                # → wallets.json (PKs saved)
npm run deploy                     # → deployed.json (suite + seeded DEX pool)
npm run fund                       # funder Disperses gas to all wallets
node scripts/run.js --profile=A    # calibrate; note suggested TARGET_TPS
#   set TARGET_TPS in .env, then:
node scripts/run.js --profile=B
node scripts/run.js --profile=C
node scripts/analyze.js --run=<runId>   # → logs/<runId>/report.md
npm run verify                     # optional: explorer verify check
```

## Distributed mode (4 IPs, public RPC — the realistic test)

The run above hits a node's **localhost** to measure the raw consensus ceiling. To test the
network **the way real traffic arrives** — from multiple IPs over the internet through
Cloudflare + the public RPC rate-limit — use the **distributed** harness:

- `flood.mjs` — lightweight per-box request flooder (proves the rate-limit protection).
- `dist-run.sh` — orchestrates load from **4 distinct source IPs** (.82/.83/.84 + home .100)
  against `rpc1/2/3.gembascan.io`, with chain monitoring + a kill-switch.

```bash
./dist-run.sh status              # what's running + chain health
./dist-run.sh flood 60 150        # 4 IPs × conc 150 × 60s → ~3000 req/s; per-IP 200/503 counts
./dist-run.sh harness A           # full tx workload from all 4 IPs
./dist-run.sh stop
```

The 4-box setup (Node 20, harness, 75-wallet slice each, public-RPC `.env`, founder-funded
wallets) **persists on the boxes** — you don't rebuild it. Full procedure + 2026-06-26 results
(protection rejects ~85% with `503` at ~2900 req/s; chain untouched): **`docs/runbooks/distributed-load-test.md`**.

## Logs (`logs/<runId>/`)
- `tx.jsonl` — one line per mined/timed-out tx (from, nonce, type, hash, block, latency, status, gasUsed)
- `blocks.jsonl` — per block (txCount, gasUsed/limit, baseFee)
- `metrics.jsonl` — periodic snapshots (submit/mined TPS, inflight, p50/p95/p99, errors)
- `node.jsonl` — CometBFT height/catching_up, mempool size, block time, disk free
- `errors.jsonl` — every submit failure + revert + timeout (classified)
- `summary.json`, `report.md`

## Safety / disk (75GB budget)
- `DISK_MIN_FREE_GB` guard + `MAX_NFT_SUPPLY` cap; soak mix avoids state-heavy ops; logs gzip-rotate.
- Funder seeded from faucet/founder; all artifacts namespaced; `Ctrl-C` drains gracefully.
