# Audit findings — independent multi-agent pass, 2026-07-13 (Phase 1: static)

31 agents, 22 candidates → **12 survived adversarial verification**, 10 refuted. Static
source review + adversarial verify only (no live/devnet exploitation yet — that's Phase 2).
Each finding tagged **[NEW]** (never audited) or **[KNOWN-OPEN]** (flagged in a prior
doc/plan but not yet fixed; several are now *empirically confirmed* here for the first time).

## HIGH

### H1 — valgate anti-domination caps are INACTIVE at genesis  [KNOWN-OPEN → now empirically confirmed]
`gemba-validator/genesis.json` valgate.params sets ONLY `min_self_bond`; `max_self_bond`
(10k GMB, §5.2) and `max_daily_bond_increase` (50 GMB/day, §6) are omitted. The nil `math.Int`
marshals to `"0"`, reads back as **non-nil zero**, so `GetParams`' nil-backfill is SKIPPED and
both enforcement points treat 0 as **"no cap"**. Verifier reproduced this with the module's own
codec. → From block 1 the max-self-bond + daily-bond caps are OFF; a single actor concentrates
consensus power with no rate limit (still needs to own the GMB → High, not Critical).
**Fix:** set both caps explicitly in mainnet genesis + make InitGenesis default zero (not just
nil) + a genesis round-trip test.

### H2 — purchase-backend settlement webhook fails OPEN → arbitrary GMB mint  [NEW]
`services/purchase-backend/src/server.js:18,91`: `whsec = process.env.GEMBAPAY_WEBHOOK_SECRET || ''`.
No guard rejects an empty secret. If deployed without the env var, the HMAC is keyed on `""` →
any attacker computes it offline. The webhook is the SOLE auth gate on `dispense()` (sends real
GMB to a buyer-chosen address) and re-validates no amount/currency. → create order (no auth, any
address, up to 10k GMB) → forge empty-key HMAC → dispense → repeat = unlimited free GMB.
**Fix:** fail closed if `whsec` empty (refuse boot / 503); re-verify paid amount+currency vs the
stored order before dispensing.

## MEDIUM

### M1 — §6 daily-bond cap bypassable via EVM staking precompile (0x…0800)  [KNOWN-OPEN, confirmed ×2]
Found independently by two finders (cosmos-valgate + evm-cosmos-boundary). The daily cap is
enforced **only in the ante** (`valgate/ante.go`); the delegation hooks
(`AfterDelegationModified`/`BeforeDelegationSharesModified`, `hooks.go:65-74`) are **no-ops**. An
EVM tx surfaces to the ante as `*MsgEthereumTx` (no match); the staking precompile's
`delegate`/`redelegate` call the staking keeper directly during EVM execution, after the ante →
cap never applied. The cap IS live on the Cosmos `MsgDelegate` path (GetParams re-defaults nil→50)
so the asymmetry is a live gap. The sibling min-self-bond *creation* bypass was fixed via the
`AfterValidatorCreated` hook; delegation was left uncovered. **Fix:** enforce at the staking
MsgServer the precompile calls (wrap Delegate/BeginRedelegate → CheckAndRecordDailyBond), keep
ante as defense-in-depth; add a precompile-delegate test asserting rejection.

### M2 — rewardstreamer FormulaParams not genesis-persisted nor gov-settable (no kill-switch)  [KNOWN-OPEN, confirmed]
`FormulaParams` (store key 0x02) drives the live capped reward path but: InitGenesis/ExportGenesis
touch only legacy `Params`; there is **no MsgUpdateFormulaParams**; `SetFormulaParams` is called
only from tests. → the active reward formula runs at **build-time defaults** (enabled, 1%/day,
cap 100 GMB), governance **cannot disable or retune it**, and any export→import silently resets it.
Supply-safe (never mints), but an operational/governance control gap. **Fix:** add FormulaParams
to GenesisState (export+import) and a gov-gated `MsgUpdateFormulaParams`.

### M3 — Critical governance tier never wired for treasury releases / reserve UUPS upgrades  [NEW]
`GembaGovernor` auto-classifies Critical only if a target is the Governor, the Timelock, or a
`criticalTarget[]` entry — but `setCriticalTarget` is **never called at deploy** (only in a test).
So `release()` (drain a reserve) and `upgradeToAndCall()` (swap a reserve to a fund-draining impl)
target the **reserve proxy** → classified **Standard (40%/51%)**, not the Critical (51%/66%) the
model (§7) promises for treasury/upgrades. A faction clearing only the Standard bar can pass a
malicious reserve upgrade and drain e.g. the 15M FoundationTreasury. **Fix:** `setCriticalTarget`
every reserve (+ economic contracts) at genesis via a governance action, AND/OR classify by
selector (`upgradeToAndCall`/`upgradeTo`/release-style) as Critical regardless of target.

### M4 — Formula reward has no aggregate budget cap → 20M reserve drains in ~3.6 yr, not ~10 yr  [NEW]
`StreamFormulaRewards` pays each bonded validator `max(10, min(100, stake×1%))` GMB/day with NO
global ceiling; only bound is MaxValidators=150. Full set at cap = 150×100 = 15,000 GMB/day =
5.48M/yr → 20M reserve gone in ~3.6 yr vs CLAUDE.md §4.3's ~2M/yr over ~10 yr. Supply-safe and
per-validator-bounded (not attacker asymmetry), but it pulls the year-10 security-budget cliff
(a declared hard launch blocker) ~6 years forward, and the docs contradict the code. **Fix:** add
a global annual budget cap (pro-rata to ~2M/yr regardless of validator count); reconcile the docs.

## LOW

### L1 — BeginBlocker ordering has no runtime assertion + WIRING.md self-contradicts  [KNOWN-OPEN]
Correct fee/reward routing depends on `feesplit → rewardstreamer → tailreward → distribution`
(enforced only by the hand-written list in the wiring patch — correct today). But `WIRING.md`'s
`SetOrderBeginBlockers` code example **omits tailreward** and the header still says "the two Phase 2
modules". A maintainer re-deriving wiring from the doc could reorder → feesplit silently skims 40%
of validator rewards. Not currently exploitable (patch is correct). **Fix:** startup assertion on
the resolved order (panic if wrong) + fix the doc.

### L2 — feemarket `min_gas_price = 0` contradicts the intended non-zero floor  [KNOWN-OPEN]
§16.8 requires a low but non-zero gas floor as the post-year-10 security budget; genesis ships 0.
Config/consistency item for mainnet, not a live exploit. **Fix:** set a small non-zero
min_gas_price in mainnet genesis.

## INFO
- **I1 [positive]** — supply/mint reconcile clean (100M, mint disabled, rewardstreamer cannot
  mint); confirms the fixed-supply core. Also: **no mainnet genesis exists yet** — the current
  file is a stale pre-regenesis testnet artifact, so all "genesis" fixes land in the mainnet
  genesis you have not built yet.
- **I2 [NEW]** — validator auto-ops daemons sign non-interactively with an **unencrypted `test`
  keyring backend** — mainnet needs an encrypted/HSM-backed key.
- **I3 [NEW]** — `services/blockchain-notifier/.env` stores a **live SMTP credential in plaintext**
  on disk (weak/reused-style password). Rotate + secret-store for mainnet.

## Refuted (NOT problems — for the record)
10 candidates were killed on verification, incl.: slashfunds pool-name interception is **correct**
in the pinned staking v0.54.3 (only a version-drift fragility, not a bug); SPOF owner keys **not
exploitable** as framed; per-validator-floor reserve-drain and the Sybil-split-into-150 both fail
(floor case is the *slow* drain, and per-validator cap has no attacker asymmetry); erc20
permissionless registration is intended and non-supply-affecting; unbonding 3d / min-self-del=1
gentx / gov-params-loose are real numbers but not exploitable as stated (still worth hardening for
mainnet as config, not vulns).

## Fix order (proposed)
1. **H2** (webhook fail-open) — 1-line-ish, real mint risk, ship now.
2. **H1** + **L2** + valgate caps — all land in the **mainnet genesis** (+ small InitGenesis guard).
3. **M1** (precompile daily-cap) — staking MsgServer wrapper (code).
4. **M3** (Critical tier wiring) — deploy-script + optional selector classifier.
5. **M2** (FormulaParams genesis/gov) + **M4** (reward budget cap) — reward-module code + docs.
6. **L1** (ordering assertion + doc), **I2/I3** (key/secret hygiene).

## Phase 2 (next) — prove them dynamically
Reproduce each as a PoC on a throwaway devnet (this box has the gembad binary): drive a precompile
delegate exceeding 50 GMB/day (M1); genesis dry-run asserting caps active (H1); forge the empty-key
webhook (H2, local); a Standard-tier reserve-upgrade proposal passing (M3); fuzz the reward math
(M4). Plus the bounded live contract-drain + RPC-hardening attacks. No live-chain interference.
