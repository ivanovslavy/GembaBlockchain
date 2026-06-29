# GembaBlockchain — 24h Endurance Test

A **low, constant, varied, revert-safe** load generator for the public **`gemba-testnet-1`**
testnet (EVM chainId **821207**), designed to run for **24 hours** from the Raspberry Pi
through the **public DNS RPCs** (`rpc1/2/3.gembascan.io`). The goal is *realism* — "everything a
real chain does" — at a sustainable rate (~4 tx/s) with **0 reverts and 99.9 %+ mined**, NOT
peak TPS.

It is a hardened fork of the proven `../stress` harness: the same pipelined nonce/collector
engine, plus three reliability fixes for multi-RPC WAN operation, a 24h `ENDURANCE` profile, a
rich state-guarded workload, and a fresh Foundry contract suite.

> **Safety:** testnet only. NEVER points at validators, the archive `.137`, or anything mainnet
> — only the public DNS RPCs. The CometBFT/disk probe is **off** (we don't touch validator
> hosts). Every workload op is state-guarded so the chain never sees an invalid tx.

---

## Folder layout

```
endurance/
  lib/                 # engine (forked from stress/lib, + 3 reliability fixes)
    wallets.js         #   FIX #1 — pin each wallet to ONE RPC
    tx.js              #   FIX #2 — retry transient submit errors; return the signed blob
    receiptCollector.js#   FIX #3 — re-broadcast a timed-out tx once before counting it
    nonceManager.js provider.js rateLimiter.js metrics.js txLogger.js nodeProbe.js
  config/
    profiles.js        # the ENDURANCE profile (ramp -> 24h steady), all env-tunable
    workloads.js       # the rich, revert-safe workload (state-guarded ops)
  contracts/           # Foundry project (new suite) — forge build/test green
    src/{Common,Tokens,Ecosystem,Diamond,Factory,Market,Staking,Batch}.sol
    test/Endurance.t.sol
    foundry.toml
  artifacts/           # {abi,bytecode} extracted by build-artifacts.mjs (Pi needs only these)
  scripts/
    build-artifacts.mjs   # forge build -> artifacts/*.json
    00-gen-wallets.js     # -> wallets.json (gitignored, 0600)
    01-deploy-suite.mjs   # deploy suite + seed GembaSwap liquidity -> deployed.json
    02-seed-wallets.mjs   # fund GMB + mint tokens + ALL approvals (so nothing reverts)
    run.js                # the load engine
    drain-to-founder.mjs  # return worker GMB to the founder (stop/cleanup)
  .env.example  package.json  README.md
```

`wallets.json`, `deployed.json`, `.env`, `logs/`, `artifacts/`, `node_modules/`,
`contracts/{out,cache,lib}` are gitignored. The Pi receives the whole folder by `scp` (incl.
`artifacts/`, `wallets.json`, `deployed.json`) so it can run with **Node only** — no forge.

---

## The three reliability fixes (vs `stress/lib`)

A senior review of running `stress` over multiple public RPCs identified three issues; all are
fixed here:

1. **Pin each wallet to ONE RPC** (`lib/wallets.js` `asSigners`). The original round-robined
   the provider per *send*, so a single wallet's consecutive manual nonces hit different nodes;
   a node that hadn't yet gossip-received the lower nonce saw a future-nonce gap and silently
   dropped the tx → timeouts and stalled nonce streams. Now `providers.all[index % n]` pins each
   wallet's whole nonce stream to one node (consensus still gossips to all validators via P2P;
   load is still spread evenly by index).
2. **Retry transient submit failures** (`lib/tx.js` `sendRaw`). On a non-benign, non-nonce error
   matching `/timeout|econn|socket|reset|fetch|429|503|txpool|mempool is full/`, the *same signed
   tx* is re-broadcast up to 3× with `80*(attempt+1)`ms backoff (idempotent — "already known" is
   benign). `sendRaw` also returns the `signed` blob for fix #3.
3. **Re-broadcast timed-out txs** (`lib/receiptCollector.js`). `track()` stores the `signed` tx;
   on the **first** timeout the collector re-broadcasts it once and grants one more full window;
   only a **second** miss is counted as a `timeout`. Recovers txs dropped from the mempool over
   the WAN. (`rebroadcasts` is surfaced in the metrics/summary.)

Two further measures (added after the first dry run surfaced WAN mempool drops) make a 24h
0-revert run robust:

4. **`MAX_INFLIGHT_PER_WALLET=1`** — at ~4 tps over 100 wallets, one unconfirmed tx per wallet
   is plenty, and it eliminates per-wallet **nonce gaps**: a tx dropped by a public RPC can no
   longer strand the wallet's higher nonces (which had caused cascading timeouts + nonce churn),
   and the rebroadcast (fix #3) can actually re-land it.
5. **Confirmation-gated producer effects** (`config/workloads.js` + `collector.onResolve`) — a
   producer op (mint / deposit / addLiq / list / deploy / propose…) does NOT mutate consumable
   state in `build()`; it attaches `req._apply`, which the engine runs **only when that tx
   mines**. So a consumer (transfer / withdraw / buy / vote / call…) only ever acts on state that
   is **confirmed on-chain** — a producer that times out leaves no phantom state, so the consumer
   can never revert. This is what turns "0 reverts" from luck into a guarantee.

The proven dynamic-fee poller (2×base+tip), benign-error tolerance, and block-scan collector are
inherited unchanged from `stress`.

---

## New contracts (Foundry) — `forge build` + `forge test` green

Self-contained, dependency-free `src` (so `artifacts/*.json` need no libs); tests use the repo's
vendored `forge-std`. All paths are CEI + `nonReentrant` on value moves (security-standards.md).

| Contract(s) | Role in the workload |
|---|---|
| `EndERC20/721/1155` (`Tokens.sol`) | open-mint test tokens (caller-chosen 721 ids) |
| `EcoRegistry`+`EcoToken`+`EcoBank` (`Ecosystem.sol`) | **multi-contract A→B→C**: `EcoBank.deposit()`→`EcoToken.reward()`→`EcoRegistry.bump()` in one tx |
| `Diamond`+`CounterFacet`+`RegistryFacet`+`LoupeFacet` (`Diamond.sol`) | **EIP-2535 Diamond**: selector→facet routing, delegatecall fallback, `diamondCut`, loupe |
| `ChildCounter`+`MiniFactory` (`Factory.sol`) | **deploy-during-run + call**: EOA `CREATE` + factory `CREATE2` (predictable addr) children, then call them |
| `CloneTarget`+`CloneFactory` (`Clones.sol`) | **EIP-1167 clones**: `cloneAndInit` (deploy+init+use in 1 tx) and `cloneDeterministic` (predicted CREATE2 addr) then init+call |
| `MiniVault` (`DeFi.sol`) | **ERC-4626-style vault**: deposit / mint / withdraw / redeem shares |
| `RewardStaking` (`DeFi.sol`) | **time-based reward staking**: stake / claim / unstake (`block.timestamp` accrual) |
| `AuctionHouse` (`Auctions.sol`) | **English** (create→bid→settle) + **Dutch** (create→buy) auctions with NFT escrow |
| `BatchMintNFT` (`NftExtras.sol`) | **ERC721A-style batch mint** (many NFTs in one tx) |
| `NftStaking` (`NftExtras.sol`) | stake an ERC721 → earn an ERC20 over time → unstake |
| `RoyaltyNFT`+`RoyaltyMarket` (`NftExtras.sol`) | **EIP-2981 royalties**: list / buy (royalty→creator) / cancel |
| `MiniGov`+`GovTarget` (`Governance.sol`) | **governance lifecycle**: propose → vote → queue → execute |
| `HopA..HopE` (`Composite.sol`) | **deep 5-hop chain** A→B→C→D→E in one tx + a **safe reentrant callback** (guarded entrypoint) |
| `Disperse` (`Composite.sol`) | one tx paying many recipients |
| `EventsHeavy` (`Composite.sol`) | many indexed events per tx (exercises the GembaScan indexer) |
| `PermitToken` (`SignedFlows.sol`) | **EIP-2612 permit**: sign off-chain → `permit()` → delegated `transferFrom` by another wallet |
| `VoucherMinter` (`SignedFlows.sol`) | **EIP-712 signed voucher** → redeem mints (typed-data + `ecrecover`) |
| `FeeOnTransferToken`+`RebasingToken` (`EdgeTokens.sol`) | edge tokens swapped via the router's `*SupportingFeeOnTransferTokens` path |
| `EnduranceMarket` (`Market.sol`), `EnduranceStaking` (`Staking.sol`), `Pinger`/`Workbench`/`BatchExecutor` (`Batch.sol`) | escrow marketplace, plain staking, batched multicall + SSTORE/compute |

`forge test` → **23 passed, 0 failed** (an assertion per op family proving it does NOT revert,
incl. EIP-712 signing via `vm.sign` and time lifecycles via `vm.warp`).

The harness also drives **LIVE** infra: `GembaSwapRouter02` `0x49Da…eEfd5`, `GembaSwapFactory`
`0x1575…6DB4`, `WGMB` `0x4A74…e8d8`, the `GembaNativePool` via factory
`0x92F0…8a99` (native-GMB liquidity + native swaps), and `GembaFaucet` `0x0147…f8aA`. Deployed
addresses for the new suite + the 5 fresh GembaSwap pairs (incl. fee-on-transfer & rebasing) +
the seeded native pool are written to `deployed.json`.

---

## Workload — "everything a real chain does", state-guarded so nothing reverts

Weighted mix in `config/workloads.js` (set `endurance`). Every op is valid for the chosen
wallet's state via two guard patterns; **no adversarial ops** (no gas bombs / intentional
reverts / oversized calldata):

- **Confirmation-gated FIFO queues** (consumer takes an entry only once the producer mined):
  `nftMint→nftTransfer`, `mktMint→mktList→mktBuy`, `royaltyMint→royaltyList→royaltyBuy/cancel`,
  `deployChild→callDeployedChild`, `factoryDeploy→factoryCallChild`,
  `cloneDeterministic→cloneInit→cloneCall`, `batchMint→nftStakeStake→nftStakeUnstake`,
  `auctionMint→createEnglish→bidEnglish→settleEnglish` / `createDutch→buyDutch`,
  `permit→permitTransferFrom`, `govPropose→govVote→govQueue→govExecute`.
- **Confirmation-gated credits** (never spend more than confirmed-mined):
  `wrapGMB→unwrapGMB`, `ecoDeposit→ecoWithdraw`, `stakeDeposit→stakeWithdraw`,
  `rwdStake→rwdClaim→rwdUnstake`, `vaultDeposit/mint→vaultWithdraw/redeem`,
  `dexAddLiq→dexRemoveLiq`, `nativeAddLiq→nativeRemoveLiq`.

~55 op types total: native transfer; ERC20 mint/transfer/approve; ERC721 mint/transfer; ERC1155
mint/transfer; WGMB wrap/unwrap; **real GembaSwap** swap/add/remove + fee-on-transfer & rebasing
swaps (supporting-fee path) + rebase; **GembaNativePool** native swaps + native add/remove;
EcosystemSim multi-hop; Diamond facet calls; EOA/factory/clone deploys + calls; ERC-4626 vault
deposit/mint/withdraw/redeem; plain + time-based reward staking; NFT batch-mint + NFT staking;
escrow marketplace + EIP-2981 royalty marketplace; English + Dutch auctions; governance
propose/vote/queue/execute; deep 5-hop chain + reentrant callback; disperse-to-many; events-heavy;
EIP-2612 permit + delegated transfer; EIP-712 voucher redeem; batched multicall; SSTORE/compute.

Gas limits are fixed per op (no `eth_estimateGas` round-trips) and budgeted for first-call-per-
wallet **cold SSTOREs** (the dry-run surfaced and fixed two cold-SSTORE out-of-gas cases).

Seeding makes every op revert-safe up front: each wallet is funded with native GMB, minted a
huge balance of TKA/TKB/TKC, and pre-approves the router (tokens **and** LP pair tokens), the
staking contract, and the marketplace (`setApprovalForAll`). DEX reserves are seeded at ~1e26
per pair, so 24h of tiny swaps never depletes or rounds output to zero.

---

## Config for the Pi

Copy `.env.example` → `.env` and set `FUNDER_PK` (testnet founder key). Key values:

```
RPC_URLS=https://rpc1.gembascan.io,https://rpc2.gembascan.io,https://rpc3.gembascan.io  # DNS only
CHAIN_ID=821207
WALLET_COUNT=100
TARGET_TPS=4            START_TPS=1   RAMP_SEC=300   STEADY_SEC=86400   # 24h
MAX_INFLIGHT_PER_WALLET=3   CONCURRENCY=20   SETTLE_MS=20000
TX_TIMEOUT_MS=120000   RECEIPT_CONCURRENCY=6     # gentle on the ~25 r/s-per-IP public RPCs
MAX_FEE_GWEI=15        PRIORITY_FEE_GWEI=2        # run.js bids 2×base+tip dynamically (5-gwei floor)
# COMETBFT_RPC unset  -> node/disk probe OFF: we do NOT touch the validators
```

At ~4 tps across 3 RPCs (pinned wallets), each RPC sees only a few requests/second for
submits + receipts + one block-scan — well under the nginx rate limit.

---

## Dry-run result (10 min, this box → DNS RPCs)

**10-min dry-run (dev box → DNS rpc1/2/3), latest clean iteration:**

| submitted | mined | reverted | failedSubmit | timedOut | softSubmit |
|---|---|---|---|---|---|
| 2025 | 2012 | **0** | **0** | **0** | 44 |

**0 reverts / 0 failed-submit / 0 timeouts** over the sample. Earlier iterations drove reverts 28 → 16 → 4 → **0** as state-guards, cold-SSTORE gas limits, and the EIP-2612 permit edge were fixed. (The run was cut by a temporary spend cap; the 13 submitted-not-yet-mined were simply in-flight at the cut — mined tracks submitted.)

---

## One-time setup (already done from the dev box)

Run **once** from a box with `forge` + the founder key; produces `wallets.json`, `deployed.json`,
funds + approves all wallets. The Pi then just runs `run.js`.

```bash
cd endurance
npm install
npm run build          # forge build -> artifacts/*.json   (needs forge)
npm run gen-wallets    # -> wallets.json (100 wallets, 0600)
npm run deploy         # deploy suite + seed GembaSwap liquidity -> deployed.json
npm run seed           # fund GMB + mint tokens + all approvals (founder pays)
# optional sanity: a short dry run
RAMP_SEC=60 STEADY_SEC=480 node scripts/run.js --profile=ENDURANCE
```

---

## Run the 24h test on the Pi

The folder is uploaded to `slavy@84.242.164.248:/home/slavy/endurance/` with `wallets.json`,
`deployed.json`, `artifacts/`, and a Pi `.env` (DNS RPCs + `FUNDER_PK`). `npm install` is done
there (Node v20, aarch64). To launch the **detached 24h run with logging**:

```bash
ssh -i ~/.ssh/gemba_claude slavy@84.242.164.248
cd ~/endurance
# detached, survives logout, full stdout log + the structured logs/<runId>/ tree:
nohup node scripts/run.js --profile=ENDURANCE > logs/endurance-24h.out 2>&1 &
echo $! > endurance.pid
```

(Defaults give the 24h run: RAMP_SEC=300, STEADY_SEC=86400, TARGET_TPS=4.)

### Monitor

```bash
tail -f ~/endurance/logs/endurance-24h.out        # live one-line dashboard
# structured logs of the latest run:
D=$(ls -dt ~/endurance/logs/ENDURANCE-* | head -1)
tail -f "$D/metrics.jsonl"                          # periodic snapshots (tps, p95, errors)
grep -c '"kind":"revert"' "$D/errors.jsonl"         # should stay 0
cat "$D/summary.json"                               # written at the end
```

The dashboard line shows: `tps s/m | inflight | p95 | sub mined rev fail to rb | fee | blk`.
Healthy = `rev 0`, `fail 0`, `to` near 0, `rb` small, mined ≈ submitted.

### Stop / drain

```bash
kill $(cat ~/endurance/endurance.pid)   # graceful: drains in-flight, writes summary.json
# return all worker GMB to the founder when finished:
node scripts/drain-to-founder.mjs
```

---

## Logs (`logs/<runId>/`)

`tx.jsonl` (one line per mined/timed-out tx), `blocks.jsonl` (per block), `metrics.jsonl`
(periodic snapshots incl. `rebroadcasts`), `errors.jsonl` (submit fails / reverts / timeouts /
rebroadcasts, classified), `summary.json` (final: submitted / mined / minedPct / reverted /
failedSubmit / timedOut / rebroadcasts). Logs gzip-rotate every `LOG_ROTATE_LINES`.

## Risks / caveats

- The public RPCs are shared with live apps and rate-limited; the run is deliberately gentle, but
  if a node is restarted/redeployed mid-run, pinned wallets on that RPC will see transient submit
  errors (retried by fix #2) — they self-heal when the node returns.
- 24h at 4 tps ≈ ~345k txs ⇒ real state growth on the testnet (expected for an endurance test).
- `deployed.json` pins the deployed addresses + the GembaSwap pairs created at seed time; re-run
  `deploy`+`seed` only if you regenerate wallets or after a regenesis.
