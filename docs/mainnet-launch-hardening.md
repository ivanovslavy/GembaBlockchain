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
- [ ] **Begin-blocker order assertion (L1)** — add a startup assertion in the app constructor that
      the resolved `SetOrderBeginBlockers` places feesplit → rewardstreamer → tailreward →
      distribution, panicking otherwise (the order is a supply/reward-routing invariant enforced
      only by a hand-written list). WIRING.md is now corrected to include tailreward.

## C. Phase 2 (devnet) — needs the full app build + a live test, do NOT rush in-tree
- [ ] **M1 — §6 daily-bond cap bypass via the EVM staking precompile.** The cap is enforced only in
      the ante, which never sees the precompile's `delegate`/`redelegate` (they call the staking
      msg server directly during EVM execution, after the ante; valgate's delegation hooks are
      no-ops). The correct fix is **out-of-tree wiring** and must be validated on a throwaway
      devnet, so it is deliberately NOT done as a rushed in-tree change (a botched consensus change
      is worse than a documented Medium rate-limit gap):
      - **Design:** wrap the staking `MsgServer` used to build the staking precompile so
        `Delegate`/`BeginRedelegate` call `ValgateKeeper.CheckAndRecordDailyBond(dstValoper, amount)`
        BEFORE delegating (rejecting over-cap); keep the ante check as CheckTx-time defense-in-depth.
        (A hook-based alternative needs a transient store key + a creation-vs-delegation flag set in
        `AfterValidatorCreated` — also app-wiring, hence still Phase 2.)
      - **Test:** drive a precompile `delegate` exceeding 50 GMB/day and assert it reverts, and that
        an equivalent Cosmos `MsgDelegate` still reverts (parity).

## D. Infra / key & secret hygiene
- [ ] **I2 — validator auto-ops daemons** (`auto-unjail`, `auto-compound`) currently sign with an
      **unencrypted `test` keyring backend**. For mainnet: move to an encrypted keyring / HSM /
      tmkms, and restrict the operator key's scope. (Auto-ops key import is an already-open checklist
      item.)
- [ ] **I3 — live SMTP credential in plaintext** in `services/blockchain-notifier/.env` (weak/
      reused-style password). **Rotate the SMTP password now** and move it to a secret store /
      env-injection; ensure the `.env` is gitignored (it is) and 0600. This is a live-service action,
      not a code change — do it on the mail host.
- [ ] Re-run the round-4 **GitHub PAT rotation** (still pending) and the `security/track3-rpc-infra/
      secret-scan.sh` before launch.
- [ ] Confirm production owners of `GembaOnRamp`/`GembaPayDispenser`/`GmbCollector`/`GembaFaucet`/
      `GembaSwapFactory.feeToSetter` are governance/Timelock (or documented operational EOAs with a
      rotation plan) — the audit refuted these as SPOFs only under the "documented operational key"
      reading; verify the deploy actually sets the intended owner.
