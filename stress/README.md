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

### Raw-ceiling test (localhost) + the 2026-06-26 finding

To measure the chain's *true* throughput (no front door), point each box at **its own node**
(`RPC_URLS=http://127.0.0.1:8545`) and run profile A. Two rounds were run:

**Round 1 (single node .100, 300 wallets, old harness):** knee at ~88–102 tps mined, but
`reason=errors` dominated by `fee_too_low` — which was actually **mis-classified "replacement
fee too low"** (a nonce-dup, not a fee floor). The chain was never the bottleneck (mempool ~0,
base fee at the 1-gwei floor).

**Harness fixed** (so the generator stops being the artifact):
- **Dynamic fee** — a 3 s poller sets `maxFeePerGas = 2× live base fee + tip` (`lib/tx.js` +
  the fee poller in `run.js`), so the bid tracks load instead of being rejected.
- **Benign-error tolerance** — `already known` / `replacement` / `coalesce` / nonce-resync are
  mempool churn (the tx is in the pool), now counted as **soft** and excluded from the knee;
  the tx hash is computed locally (`keccak256(signed)`) so it's tracked even when the RPC
  response is unparseable. Classifier fixed (`replacement` ≠ `fee_too_low`).
- **Env-tunable concurrency** (`CONCURRENCY=…`) — 600 thrashes a small box.

**Round 2 (all 4 nodes, localhost, tuned):** `hardFail=0`, errors gone. The chain took real
load (~50 M gas/block, ~50 % utilisation) **and still wasn't the bottleneck** — base fee stayed
at the ~1-gwei floor, `num_unconfirmed_txs` ~0. The cap is now the **generation hardware**: the
4-core Contabo validators, which must also run consensus, thrash at load ≈ 8 even at
`CONCURRENCY=150`, and their CPU-starved block-scan collector inflates p95 → an early p95 knee.
The 8-core home node (.100) stayed at load ~1. **Conclusion:** the chain has large headroom; you
cannot saturate it by generating load *on the validators themselves* (4-core, double-duty). A
true consensus ceiling needs **dedicated (non-validator) generator boxes** — out of scope here
(prod boxes excluded, no VM provisioning). The harness itself is no longer the limit.

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
