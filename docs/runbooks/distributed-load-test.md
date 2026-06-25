# Runbook — Distributed load & rate-limit protection test (4 IPs, public RPC)

**Goal.** Drive load against GembaBlockchain the way real traffic arrives: from **multiple
distinct source IPs, over the internet, through Cloudflare + the public RPC endpoints**
(`rpc1/rpc2/rpc3.gembascan.io`) — **never** localhost. This validates the public-RPC
**rate-limit protection** (does the front door actually throttle abuse?) and the chain's
health under that traffic. Complements the raw-ceiling test in `stress/README.md` (which
hits a node's localhost `:8545` to measure consensus throughput, bypassing the front door).

> **The setup below already exists and persists on the 4 boxes — you do NOT redo it.**
> Next time: `./dist-run.sh fund` (only if the wallets are dust) → `./dist-run.sh flood`
> or `./dist-run.sh harness`. That's it. (Established 2026-06-26.)

## Topology — 4 load boxes = 4 source IPs

| Box | Role | Use here |
|---|---|---|
| `13.140.139.82` (contabo-1, rpc3) | validator | **load source** (hits public rpc1/2/3 over internet) |
| `13.140.139.83` (contabo-2, rpc1) | validator | load source |
| `13.140.139.84` (contabo-3, rpc2) | validator | load source |
| `88.203.191.208` (home, .100, val-3) | validator | load source (8 cores — heaviest) |

- **Each box runs the load generator and fires at the PUBLIC endpoints over the internet**
  (`RPC_URLS=https://rpc1.gembascan.io,https://rpc2.gembascan.io,https://rpc3.gembascan.io`,
  round-robin). The traffic leaves the box → Cloudflare → nginx (per-IP `limit_req`) → node.
  **Monitoring** (`COMETBFT_RPC`) uses the box's *local* `:26657` — read-only, not load.
- **NEVER use `.162` (gembait prod) or `.137` (archive/explorer prod) as load sources.**
- Validators double as load sources here (CPU contention risk — see Safety). Acceptable on
  testnet; watch block production and stop if liveness is threatened.

## Persistent per-box setup (already done — for reference / rebuild)

On every box, `/home/slavy/stress/` contains (owned by `slavy`, runs without sudo):
- Node 20 (`/usr/bin/node`), the harness (code + `node_modules` + `artifacts/` + `deployed.json`).
- `flood.mjs` in `/home/slavy/` (lightweight async flooder).
- `wallets.json` = this box's **disjoint 75-wallet slice** (300 wallets split 4×75 so no two
  boxes ever drive the same nonce). Slices: .82=[0:75] .83=[75:150] .84=[150:225] .100=[225:300].
- `.env` pointing at the **public** RPCs:
  ```
  CHAIN_ID=821207
  RPC_URLS=https://rpc1.gembascan.io,https://rpc2.gembascan.io,https://rpc3.gembascan.io
  COMETBFT_RPC=http://127.0.0.1:26657      # local node, monitoring only
  NODE_DATA_DIR=/home/slavy                 # same FS as the node data (disk guard)
  DISK_MIN_FREE_GB=10
  MAX_FEE_GWEI=30 ; PRIORITY_FEE_GWEI=2
  WALLET_COUNT=75 ; FUND_PER_WALLET=2.0
  LOG_DIR=./logs
  ```
- The **300 wallets are funded from the founder** (5% treasury, EVM
  `0x5578c75F22dE0bf1caA4BdD46BA28406C696a5dC`), 2 GMB each via the `Disperse` contract.

To rebuild from scratch (only if a box is wiped): install Node 20 (NodeSource), copy
`/home/slavy/stress` (tar it from any box that has it — it's ~5 MB incl. node_modules),
drop the box's wallet slice as `wallets.json`, write the `.env` above, and `fund`.

## How to run (push-button) — `stress/dist-run.sh` from the dev box

```bash
cd stress
./dist-run.sh status                 # what's running on each box + chain health
./dist-run.sh fund                   # ONLY if wallets are dust — founder refills all 300
                                     #   (needs stress/.env on the dev box with FUNDER_PK=<founder hex>;
                                     #    export it: gembad keys export founder --unarmored-hex --unsafe
                                     #    --keyring-backend test --keyring-dir wallet-backup/tmp-regenesis/node0)

# Rate-limit protection test (proves the front door throttles abuse):
./dist-run.sh flood 60 150           # 60s, conc 150/box → ~3000 req/s aggregate; prints per-IP 200/503 + chain health

# Realistic tx workload (native/ERC20/721/1155/DEX/adversarial mix):
./dist-run.sh harness A              # calibration ramp; then B (2h) / C (4h soak)
./dist-run.sh monitor 120            # watch chain while harness runs
./dist-run.sh stop                   # kill all load on all 4 boxes

# After a harness run, pull logs/<runId>/ from a box and: node scripts/analyze.js --run=<runId>
```

The founder private key lives **only on the dev box** (gitignored `wallet-backup/`); it is
never copied to the load boxes (they don't need it — wallets are pre-funded).

## Findings — 2026-06-26 baseline

**Rate-limit protection WORKS (decisively).** Peak distributed flood — 4 IPs × conc 150 ×
60 s = **177,236 requests (~2,889 req/s aggregate)**:
- **~151,000 (~85%) rejected by nginx with `503`** (the `limit_req` default reject status);
  only ~24,800 (~14%) accepted. Per-IP the front door caps throughput to roughly the
  configured rate + burst.
- **The chain never saw the load:** `num_unconfirmed_txs` stayed **0** the entire minute,
  blocks advanced steadily (~5.1 s), all **4/4 validators bonded**, total supply constant at
  99,999,980.1 GMB. The excess is dropped at the edge — it never reaches the mempool/consensus.
- A single IP trips it too: 200 parallel reqs → ~60% `503`; the burst (~50) is absorbed, the
  rest rejected. Under the heaviest box, a few `500/502` also appeared (origin briefly strained)
  but `503` dominated.

**Realistic tx workload — chain healthy, but the public path self-throttles the *generator*.**
With the full workload mix the chain stayed healthy (mempool ~0, base fee at the 1-gwei floor),
but the harness couldn't drive high *chain* load through the public path: the **receipt
collector polls `eth_getTransactionReceipt` over the rate-limited public RPC and gets throttled**,
so observed tx latency balloons (p95 15–33 s) and the per-wallet inflight cap pins submit-TPS
low. **Consequence:** the harness's auto-knee (profile A) is **unreliable on the public path** —
it reports a falsely-low ceiling that reflects receipt-poll throttling, not the chain. For the
true consensus/throughput ceiling, run the harness against a node's **localhost** (`stress/README.md`).

**Bottom line.** You cannot push the *chain* to "very high load" through the public endpoints —
**because the protection works**: the per-IP rate-limit rejects the excess at the edge before it
reaches the node. That is the intended behaviour, demonstrated end-to-end from 4 real IPs.

## Safety

- Load generators run **on the validators** → CPU contention with consensus. Watch
  `./dist-run.sh monitor`; if `catching_up=true` appears or block height stalls on ≥2 boxes,
  `./dist-run.sh stop` (a halt needs ≥2/3 voting power; 4 validators tolerate 1 down). A halt is
  recoverable (`docs/runbooks/halt-recovery.md`); on testnet it is acceptable.
- Slashing from missed blocks under load now redirects to the faucet (zero-burn, `x/slashfunds`,
  proven 2026-06-26) — a self-inflicted downtime slash does not reduce supply.
- Keep load on the **public RPCs only**. Do not aim it at `.162`/`.137` (production).
