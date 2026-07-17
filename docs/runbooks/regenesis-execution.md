# Runbook — GembaBlockchain regenesis execution (staged)

Executes the regenesis locked in `docs/GembaBlockchain_Нова_Логика_Регенезис.md` §0. Done in
**safe, verified stages** (spec §20): code → local STAGING dry-run → live testnet cutover →
contracts → dApps → tests. **Nothing destructive on the live testnet or the production .162 dApp
server until the local staging dry-run is green + a full backup exists.** No PK ever leaves
`wallet-backup/` (gitignored); WA preserved; CA preserved via CREATE2.

> **Status legend:** ✅ done · 🔨 code-ready, needs wiring/test · ⏳ pending

> **✅ PREP COMPLETE — READY FOR THE OFFICIAL GENESIS (2026-06-26).** Everything before the live
> cutover is built, tested and dry-run-validated locally: reward formula (capped, recirculated,
> supply-invariant — proven on a live local chain), min/max self-bond + 50/day cap, ~3s blocks,
> 5 gwei fee, faucet 0.1/day, 2-tier governance (40/51 vs 51/66, auto-classified), genesis allocation
> (10K validators, reward reserve 29.96M, 100M total — validated), CREATE2 on every deploy script
> (CA preserved). Full suites green: chain Go + **122 Foundry tests**. Remaining = **Stage E only**:
> the deliberate, destructive LIVE cutover (backups → coordinated reset of the 4 validators with the
> regenesis binary + real-WA genesis → CREATE2 redeploy → re-verify the 5 dApps). That step is the
> founder's go/no-go.

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

## Stage B — genesis allocation (✅ dry-run validated; ⏳ swap in real WA for live)
The allocation logic is in `init-gembad-multinode.sh` and **dry-run validated** (4-validator genesis:
validators 10K each, reward reserve 29,960,000 = 20M + 9.96M reclaimed circulation, supply 100M,
gentx valgate-valid, genesis VALID). For the LIVE regenesis the ONLY change is using the **real
testnet wallets (WA)** instead of fresh devnet keys — balances reset, addresses preserved:

- **Validators (preserve valoper):** import the real `val0..val3` operator keys from
  `wallet-backup/PRIVATE-KEYS.md` into the genesis-builder keyring and gentx from THEM (10K each).
  Real operators: `val0 cosmos1u6zhxs… val1 cosmos19527lf… val2 cosmos1vayp2t… val3 cosmos10d6u5g…`.
- **Reserve buckets (preserve addresses):** the rewardstreamer + faucet **module** accounts are
  deterministic (unchanged). The EOA buckets use the real addresses: `founder cosmos124uvwh…`,
  `foundation cosmos1kghqe0…`, `dao cosmos1s3fuvg…`, `contingency cosmos1muvra3…` (all in wallet-backup).
- mint inflation 0; the formula/faucet/governance params baked in; total stays 100,000,000 GMB.

> PK safety: the real operator keys come from `wallet-backup/` (gitignored) only on the genesis box;
> never printed/committed. The genesis file holds only ADDRESSES (public) + balances.

## Stage C — contracts via CREATE2 (🔨 mechanism proven; per-script conversion is the rollout)
CREATE2 address = f(deployer, salt, init-code) — **no nonce term** → same deployer + salt + bytecode
gives the **same address** on a fresh chain. Proven: `contracts/test/Create2Determinism.t.sol` (2 tests:
address is nonce-independent + matches the prediction). So CA survive the regenesis → dApp configs stay
untouched. (Plain `new C()` = CREATE = nonce-dependent → addresses would shift.)

**Salt scheme** (fixed, versioned): `keccak256("gemba.<contract>.v1")` — e.g. `gemba.governor.v1`,
`gemba.timelock.v1`, `gemba.votes.v1`, `gemba.faucet.v1`, `gemba.foundation.v1`, `gemba.dao.v1`,
`gemba.contingency.v1`, `gemba.emergencypause.v1`, `gemba.dripfaucet.v1`,
`gemba.ticketing.v1`, `gemba.perks.v1`, `gemba.forwarder.v1`, `gemba.checkin.v1`, `gemba.accessnft.v1`,
*(`gemba.onramp.v1` retired — GembaOnRamp removed 2026-07-17, no public-sale contract)*,
plus the DEX (factory/router/WGMB/pairs).

**Conversion (mechanical, follow the pattern):** in each deploy script change `new C(args)` →
`new C{salt: keccak256("gemba.<c>.v1")}(args)` (Foundry routes it through the canonical CREATE2 factory
0x4e59…, present on the chain). Same founder + salt + bytecode ⇒ identical address every regenesis.
Verify each on Blockscout. **dApp contracts (GembaTicket/GembaPass/Escrow/GembaWin/EduChain) live in
their own repos — their deploy scripts must adopt the same CREATE2+salt scheme to keep THEIR CA.**

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
