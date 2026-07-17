# Mainnet launch hardening checklist

Operationalizes the audit-finding fixes that are NOT pure code (genesis config, infra, and the one
fix that needs devnet validation). Companion to `docs/audit-findings-2026-07-13.md` (the findings)
and the code fixes already merged. There is **no mainnet genesis yet** — build it against this list.

## A. Code fixes already merged (for reference)
- **H2** purchase-backend fails closed on empty webhook secret + re-validates amount/currency.
- **H1** valgate `InitGenesis` defaults omitted (nil) caps to `DefaultParams` (caps ship active even
  if genesis omits them). Belt-and-suspenders: still set them explicitly in genesis (§B).
- **M2** rewardstreamer `FormulaParams` carried in `GenesisState` (survives export/import).
- **M4** rewardstreamer aggregate daily reward budget (`MaxTotalPerDay`, default ≈2M GMB/yr).
- **M3** GembaGovernor: reserve `release` + UUPS `upgrade*` are Critical tier by selector.

## B. Mainnet GENESIS config — set explicitly, verify before launch (irreversible)

### DECIDED VALUES (2026-07-17, owner) — feed these into the mainnet genesis builder
The devnet builder (`init-gembad-multinode.sh`) already sets caps/supply/unbonding/feemarket
correctly; it uses DEVNET-loose gov + a devnet-amplified reward rate. For mainnet set:
- **feemarket.min_gas_price = `5000000000` agmb (5 gwei).** ✓ confirmed.
- **staking.unbonding_time = `1814400s` (21 days).** ✓ already correct.
- **rewardstreamer:** `annual_reward = 2,000,000 GMB`, `max_total_per_day = 5479 GMB` (the hard
  emission backstop = 2M/365, so a mis-set block count can't over-emit). Block-time MEASURED on the
  live testnet 2026-07-17 = **2.402s avg over 100k blocks** → set BOTH consistently:
  `params.blocks_per_year = 13,140,000` and `formula_params.blocks_per_day = 36,000` (~2.4s). The
  devnet's `blocks_per_year=2000` / `blocks_per_day=28800` are devnet-amplified — DO NOT ship them.
  Re-measure real mainnet block-time weeks 1-4 and reconcile.
- **gov:** `voting_period = 259200s` (3 days); `expedited_voting_period = 86400s` (1 day, < voting);
  `min_deposit = 10,000 GMB` (`10000000000000000000000 agmb` — devnet was 1e7 agmb ≈ 0, spam risk);
  `quorum = 0.334`, `threshold = 0.5`, `expedited_threshold = 0.667` (Critical ≥66% ✓); governance
  **Timelock min delay 24–48h**.
- **valgate:** `max_self_bond = 10,000 GMB`, `max_daily_bond_increase = 50 GMB`. ✓ already correct.
- **Supply:** mint disabled (inflation 0), total = exactly 100,000,000 GMB, 20M reward reserve in the
  rewardstreamer module account. ✓ already correct in the builder's "mainnet split".
- **GembaVotes exclusion set** — POPULATE at genesis (every reserve/faucet/foundation/DAO/onramp/
  contingency address); verify `getVotes()==0` for each. ⏳ owner to populate (highest-severity item).

- [ ] **valgate.params** — set `max_self_bond` (10,000 GMB) and `max_daily_bond_increase` (50 GMB)
      explicitly (H1). Don't rely on the code default alone; a reviewer must see the numbers.
- [ ] **feemarket.min_gas_price > 0** (L2) — a small non-zero floor (e.g. 1e9 agmb / 1 gwei) so the
      post-year-10 security budget isn't zero. Testnet ships 0.
- [ ] **rewardstreamer.formula_params** — set the intended `enabled`, `cap_per_day`, `rate_per_day`,
      and `max_total_per_day` (M4 budget) so the reward economics are explicit in genesis, not
      build-time defaults.
- [ ] **gov params** — raise from testnet-loose: voting_period (days not 30s), quorum + threshold +
      the two-tier supermajority high (Critical ≥ 66%), a real Timelock min delay (§7).
- [ ] **staking.unbonding_time** 7–21 days (testnet 3d) — this is the slashing/security window.
- [ ] **GembaVotes exclusion set POPULATED at genesis** — every reserve/faucet/foundation/DAO/
      contingency address excluded from voting (the single highest-severity launch item; testnet
      left it empty until a manual governance cycle). Verify `getVotes()==0` for each reserve.
- [ ] **Supply reconciliation** — mint disabled, allocation sums to exactly 100,000,000 GMB, the
      20M reward reserve is in the rewardstreamer module account (audit I1 confirmed this holds).
- [x] **Begin-blocker order assertion (L1) — DONE 2026-07-17.** `chain/x/wiring` validates the
      RESOLVED `OrderBeginBlockers` (feesplit → rewardstreamer → tailreward → distribution;
      presence, uniqueness, relative order) and the patched app constructor panics on any
      violation (`gembad-wiring.patch`). Unit-tested (good order + 4 violation classes);
      full `build-gembad.sh` green; runtime smoke: node constructs the app cleanly.

## C. Phase 2 (devnet) — needs the full app build + a live test, do NOT rush in-tree
- [x] **M1 — §6 daily-bond cap bypass via the EVM staking precompile. DONE + DEVNET-VALIDATED
      (commit 677e5e2, fix; re-validated end-to-end 2026-07-17).** The cap was enforced only in the
      ante, which never saw the precompile's `delegate`/`redelegate` (they call the staking msg
      server directly during EVM execution, after the ante). **Fix (in-tree, in the genesis binary):**
      `chain/x/valgate/keeper/staking_msgserver.go` = `CapEnforcingStakingMsgServer`, a staking
      `MsgServer` decorator that calls `CheckAndRecordDailyBond(dstValoper, amount)` before
      `Delegate`/`BeginRedelegate` (all other methods pass through). `chain/gembad/gembad-wiring.patch`
      builds the staking precompile from the cap-enforcing server and `EVMKeeper.RegisterStaticPrecompile`
      overrides the default — so ONLY the precompile server is wrapped; the Cosmos path (ante) and the
      precompile path (wrapper) each check the SAME valgate counter exactly once (no double-count).
      **End-to-end validation 2026-07-17 (this box):**
      - Unit: `chain/x/valgate/staking_msgserver_test.go` → `go test ./x/valgate/...` PASS (over-cap
        precompile delegate/redelegate rejected before the inner server).
      - Build: clean `build-gembad.sh` from scratch — patch applies cleanly to pinned cosmos/evm
        v0.7.0, full binary built (version 677e5e2-dirty).
      - Live devnet (`gemba-1` / EVM 821206, 4 nodes, `--json-rpc.enable`, genesis cap 50 GMB/day):
        precompile `delegate` 40 GMB via EVM JSON-RPC → MINED status=1 (under cap); +20 GMB
        (60 > 50) → **REVERTED** — the bypass is closed. Cosmos-path parity: a subsequent Cosmos
        `MsgDelegate` +15 GMB was rejected with "already added 40000000000000000000 today" — proving
        BOTH paths share ONE daily counter (precompile 40 + cosmos 15 = 55 > 50 → rejected).
      Consensus code, already committed → ships in the mainnet genesis binary (built via
      `build-gembad.sh`), NOT a later governance upgrade. No `genesis.json` change needed for M1.

## D. Infra / key & secret hygiene
- [x] **I2 — auto-ops `test` keyring backend. RESOLVED / risk-accepted 2026-07-17 (owner).** The
      validator hosts are reachable ONLY via SSH key auth — no outsider gets a shell, so no path to
      read the keyring at rest. Left as-is by decision; no change.
- [x] **I3 — SMTP credential in `services/blockchain-notifier/.env`. RESOLVED / risk-accepted
      2026-07-17 (owner).** Mail host is SSH-key-only; the `.env` is gitignored and unreadable
      without a shell. Left as-is by decision; no change.
- [x] **Round-4 GitHub PAT / secret-scan. RESOLVED / risk-accepted 2026-07-17 (owner).** Infra is
      SSH-key-only; owner accepts the current secret posture across all three key/password items
      above. No rotation performed by decision.
- [ ] Confirm production owners of `GembaPayDispenser`/`GmbCollector`/`GembaFaucet`/
      `GembaSwapFactory.feeToSetter` are governance/Timelock (or documented operational EOAs with a
      rotation plan) — the audit refuted these as SPOFs only under the "documented operational key"
      reading; verify the deploy actually sets the intended owner. (`GembaOnRamp` dropped from this
      list — contract removed from the codebase 2026-07-17, nothing to own.)
- [ ] **I4 — validator node storage config FROM GENESIS (root cause: testnet disk-fill 2026-07-15).**
      On 2026-07-15 validator `.82` filled its 72G disk under load and crash-looped (jailed + rpc3
      down); the culprit was chain DATA: `application.db` 36G (`pruning="default"` keeps 362,880
      versions) + `tx_index.db` 13G, with journald uncapped. **Mainnet validators must launch as
      lean pruned nodes, configured at provisioning (NOT retroactively — applying `keep-recent=100`
      to an already-fat node grinds the 362k-version backlog and makes catch-up fall behind the
      chain; the clean fix is state-sync bootstrap or correct-from-genesis config):**
  - `app.toml`: `pruning="custom"`, `pruning-keep-recent="100"`, `pruning-interval="10"` from first
    start (a node pruned from genesis never accumulates the backlog, so it stays small AND syncs fine).
  - `config.toml`: `[tx_index] indexer="null"` on validators (EVM receipts use the app-side indexer;
    CometBFT tx-search lives on the archive/explorer only).
  - journald drop-in cap `SystemMaxUse=500M` (uncapped default = 10% of disk).
  - Keep the dedicated **archive** node (`pruning="nothing"`) as the sole history/explorer source, so
    pruned validators lose nothing globally.
  - The offline `gembad prune` subcommand is BROKEN in the current `evmd` build (`leveldb: closed`,
    reclaims nothing) — do not depend on it. Add a disk-usage watchdog/alert (auto-unjail already exists).
