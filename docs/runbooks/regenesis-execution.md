# Runbook — GembaBlockchain regenesis execution (staged)

Executes the regenesis locked in `docs/GembaBlockchain_Нова_Логика_Регенезис.md` §0. Done in
**safe, verified stages** (spec §20): code → local STAGING dry-run → live testnet cutover →
contracts → dApps → tests. **Nothing destructive on the live testnet or the production .162 dApp
server until the local staging dry-run is green + a full backup exists.** No PK ever leaves
`wallet-backup/` (gitignored); WA preserved; CA preserved via CREATE2.

> **Status legend:** ✅ done · 🔨 code-ready, needs wiring/test · ⏳ pending

## Stage A — economic-engine code

### A1 — anti-domination (✅ done, on main)
min/max self-bond 1,000/10,000 at entry + **50 GMB/day** bond-increase cap (`x/valgate`, gov-tunable,
deterministic, non-halting; auto-compound script clamps). 11 tests.

### A2 — reward formula `max(10, min(100, stake×rate))`/day (🔨)
Replaces the fixed `AnnualReward` stream with a **per-validator, capped** payout. Design (so it is
implemented once, correctly):
- **Params** (gov-tunable): `RewardRatePerDay` (LegacyDec, 0.01), `RewardFloorPerDay` (Int, 10 GMB),
  `RewardCapPerDay` (Int, 100 GMB), `BlocksPerDay` (uint64, ~28,800 at 3s). Store **separately**
  from the proto `Params` (its own KVStore key + getter/setter) OR extend the proto with full wire
  support — do NOT add JSON-only fields to the proto `Params`, since `MsgUpdateParams` (proto) would
  zero them. **Recommended: a dedicated `FormulaParams` key** (clean, no proto surgery).
- **Keeper deps:** inject a read-only staking keeper (`IterateBondedValidatorsByPower`) + the
  distribution keeper (`AllocateTokensToValidator`). Bank stays mint/burn-free (§3.1).
- **BeginBlocker (replaces StreamRewards):** for each bonded validator `v`:
  `daily = max(floor, min(cap, v.Tokens×rate))`; `perBlock = daily / BlocksPerDay`. Sum →
  `total`; `total = min(total, reserveBalance)`. Move `total` reserve→distribution module (bank),
  then `AllocateTokensToValidator(v, perBlock)` for each (commission/delegator split handled by
  distribution). Reserve depleted → stream 0 (fees take over). Fail-soft + skip-counter (AU-1).
- **Wiring:** edit `chain/gembad/gembad-wiring.patch` so `rewardstreamerkeeper.NewKeeper` also
  receives the staking + distribution keepers. Validate the patch applies against the pinned evmd.
- **Tests:** mock staking (validators of 1k/5k/10k/20k) + distribution; assert 10k→100/day,
  20k→100/day (cap holds), 1k→10/day (floor), 5k→50/day; reserve depletion → 0; supply invariant.
- **Deterministic:** only block height / `ctx.BlockTime()`; identical on every node.

### A3 — block ~3s + 5 gwei fee (✅ params set in `gemba.params.sh`)
### A4 — faucet 0.1 GMB/day per-acct+per-IP (🔨) — `GembaDripFaucet` already on-chain-cooldown; set
drip=0.1, cooldown=1day; service keeps the per-IP limit. governance 2-tier (40/51 std, 51/66 crit,
3-day period) — set Governor quorum/threshold/voting-period + the category map (⏳).

## Stage B — genesis allocation (⏳)
New `genesis.json` from `chain/testnet` generator with §0 numbers:
- **WA preserved** (same addresses; balances reset to the genesis allocation).
- The reserve/founder/circulation splits **as already in the current config** (§11 — don't redefine).
- **+8M** (the ~2M idle on each of the 4 validator operator accounts) folded into the **validator
  reward reserve** module account.
- 4 genesis validators funded **exactly 10,000 GMB each from the founder** (gentx / pre-fund).
- mint inflation 0; the A2 formula/faucet/governance params baked in.

## Stage C — contracts via CREATE2 (⏳, preserves CA)
Rework deploy scripts to a CREATE2 factory + **fixed salts** so every contract redeploys to the
**same address** after regenesis → dApp configs untouched. Redeploy governance/treasury/DEX/onramp/
tickets/perks/access + drip-faucet; **verify each on Blockscout**.

## Stage D — local STAGING dry-run (⏳, MANDATORY before live)
Run the WHOLE thing on a throwaway local 4-node chain first: regenesis → contracts (CREATE2, confirm
identical addresses) → the §18 checklist → tests. Only when green proceed to live.

## Stage E — live testnet cutover (⏳, destructive — deliberate, with backups)
1. **Full backup** of every validator + the explorer DB.
2. Stop all nodes; install the regenesis binary (the A2 build) + new genesis on all 4; `unsafe-reset-all`.
3. Start; confirm 4/4 bonded, 10k each, ~3s blocks, params correct (§18 checklist).
4. CREATE2-redeploy contracts → **confirm addresses match the old ones** → Blockscout verify.
5. **dApps on PRODUCTION .162:** because CA are unchanged (CREATE2), **do NOT touch the dApp configs**;
   only re-verify + E2E-test each (GembaTicket, GembaPass, Escrow, GembaWin, EduChain).
6. Re-run stress + security suites (§23).

## Stage F — before MAINNET (external, not code)
Independent audit of the custom Go logic (reward formula, daily cap, slash→faucet, fee split,
governance tiers) + MiCA legal review of GMB/GembaPay (§16). Hard blockers.

---
**PK safety:** operator/founder keys only from `wallet-backup/` (gitignored); never printed/committed;
key import onto boxes via `unsafe-import-eth-key` over SSH only, shredded after.
