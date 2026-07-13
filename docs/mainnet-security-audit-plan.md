# Mainnet Security Audit Plan — GembaBlockchain

Independent, adversarial pre-mainnet audit. Planned 2026-07-13. **This is the plan only —
nothing here has been executed.** Chain: `gemba-testnet-1` / EVM 821207 (cosmos/evm v0.7.0 +
5 custom modules + ~25 Solidity contracts).

## 0. Posture & what prior work already established

Prior coverage is **strong and should NOT be re-litigated blindly**: 5 static audit rounds
(12→9→10→6→8 findings, 0 Crit/High/Med surviving), a live pentest (P-1 repo mnemonic → swept +
gitleaks CI; **P-4 deployed binary lacked `x/slashfunds` so slashes BURNED 19.9 GMB → fixed &
proven live**), a 38-agent live drain re-audit (5 attacks reverted), and a `security/` harness
(Foundry adversarial Track 1, devnet consensus Track 2, RPC Track 3, dApp Track 4, 40 live
read-only invariants, `collector-attack.mjs`). The fund-security core (Timelock reserves,
fixed-supply/no-mint, reserves-never-vote, RLS PII, soulbound access) is low residual risk.

**This audit concentrates net effort where prior coverage is thin or explicitly disclaimed.**
Each track below is tagged **[RE-VERIFY]** (covered before — confirm it still holds after all the
changes) or **[NEW]** (never tested / explicitly out of scope in every prior report).

## Findings the recon ALREADY surfaced (verify + fix first)

These came out of the planning recon and are concrete starting points, not hypotheticals:

1. **valgate daily-bond-cap EVM-precompile bypass** — `MaxDailyBondIncrease` (§6 anti-domination)
   is enforced **only in the ante** (`valgate/ante.go:46-75`); the staking delegate hooks
   (`AfterDelegationModified`, `BeforeDelegationSharesModified`) are **no-ops** (`hooks.go:65-75`).
   A delegate/redelegate via the EVM staking precompile (0x…0800) skips the ante → **daily cap
   not applied for EVM users** while Cosmos `MsgDelegate` is capped. (min/max-self-bond WAS
   hardened via the hook; the daily cap was not.) Likely-real; verify precompile path & fix.
2. **rewardstreamer FormulaParams genesis gap** — `keeper/genesis.go` exports/imports only legacy
   `Params`; `FormulaParams` (store key 0x02) is neither. A chain-halt export→import (upgrade/
   regenesis) **silently resets FormulaParams to defaults** (enabled, 1%/day, floor 10 / cap 100),
   and there is **no MsgUpdateParams path** for them → effectively **un-tunable by governance** and
   reset-on-upgrade. Changes validator economics silently.
3. **Mainnet genesis gaps (highest severity cluster):**
   - **Reserves NOT excluded from `GembaVotes`** at genesis (§4.1 flags it open on testnet;
     LiveGov.t.sol tests the failure mode). ~90% of supply in reserves → if seeded unfixed, the
     treasury electorate is captured. **#1 launch item.**
   - **valgate `max_self_bond` and `max_daily_bond_increase` unset** on testnet genesis → code
     treats nil/0 as **"no cap"** → §5.2 anti-domination + §6 daily cap are **inactive**. Must be
     explicitly populated for mainnet.
   - **`feemarket.min_gas_price = 0`** — §16.8 requires a low but **non-zero** gas floor as the
     post-year-10 security budget. Zero undermines it.
   - Gov params testnet-loose (voting 30s, quorum 0.334, threshold 0.5); §7 needs long timelock +
     high quorum + 66–75% supermajority. Unbonding 3d (§5.5 wants 7–21d).
4. **feesplit BeginBlocker ordering dependency** — supply/reward routing depends on order
   `feesplit → rewardstreamer → tailreward → distribution` (patch 116-120). Reordered, 40% of each
   validator reward is silently skimmed to the faucet. `WIRING.md` example even omits `tailreward`
   (doc/impl drift). Make the order a first-class asserted invariant.
5. **slashfunds over-broad `BurnCoins` interception** — redirects on **pool name only**
   (`BondedPoolName`/`NotBondedPoolName`), assuming staking's only such burn is `Slash`. Any new
   burn caller / renamed pool in the pinned staking version silently mis-routes or burns → breaks
   I1/I2. Enumerate all such call sites in the exact staking version.
6. **Native-denom mint surface** — the ONLY modules with Minter/Burner perms are upstream
   **`x/vm` and `x/erc20`** (all 5 custom modules are nil). Any path where the EVM/erc20 bridge can
   mint the native `agmb` denom breaks the fixed-supply invariant. This is THE supply attack surface.

---

## Tracks

### Track C — Upstream Cosmos EVM / evmd  **[NEW — declared HARD launch blocker, ADR-006]**
Largest unaudited surface; gates mainnet by the project's own §16.6.
- Pin exact `cosmos/evm` version (build script fetches `v0.7.0`); review its advisories/CVEs and
  v1 GA status (the launch gate).
- Supply integrity of the two minters (`x/vm`, `x/erc20`): prove the **native staking denom cannot
  be minted** via the erc20↔bank bridge / token-pair registration.
- Diff `gembad-wiring.patch` against pristine `evmd` — confirm the wiring introduces no regression
  (maccPerms grant nil to the 5 custom modules; restricted BankKeepers actually passed;
  slashfunds decorator wraps ONLY staking's bank arg, never `app.BankKeeper`).
- **Recommendation:** engage an external specialist firm for Track C + Track B — these two are the
  launch blockers and warrant a second independent set of eyes beyond in-house.

### Track B — EVM⇄Cosmos boundary / precompiles  **[NEW — only staking precompile examined before]**
- Audit **every** active precompile (`ActiveStaticPrecompiles`): bank, distribution, gov, staking,
  ICS20, bech32, etc. — access control, reentrancy back into EVM contracts, gas accounting.
- Can the EVM reach any custom-module msg server? (feesplit/valgate/etc. authority is gov-only —
  confirm no EVM path forges the gov module address.)
- Interaction of `MsgEthereumTx` with the full ante chain (only valgate's decorator was scrutinized).
- The valgate precompile-bypass (finding #1) lives here.

### Track A — Custom Cosmos economic modules  **[RE-VERIFY supply/params; NEW depth/fuzz]**
Prior tests prove the supply invariant + param-tunability happy path only.
- **Go native fuzzing** of `rewardstreamer` formula (`types/formula.go`, `formula_stream.go`):
  overflow, truncation-drift accumulated over millions of blocks, div-by-zero at edge bonded
  ratios, reserve-near-empty pro-rata scaling — assert conservation & no coins stranded in the
  distribution module (would break distribution's balance==outstanding+pool invariant).
- **BeginBlocker ordering** system test (finding #4) + a runtime `SetOrderBeginBlockers` assertion.
- FormulaParams genesis gap (finding #2): reproduce export→import reset; add export/import + a gov
  Msg path; test.
- valgate daily-cap bypass (finding #1): drive a precompile delegate, assert it escapes the cap;
  fuzz day-rollover boundaries; check CheckTx/DeliverTx double-count.
- `slashfunds` (finding #5): multi-validator simultaneous slash, partial-slash rounding, faucet in
  odd state; enumerate bonded/notBonded burn callers in pinned staking.
- `tailreward` year-10 activation transition & the "recirculated-not-minted" funding path (no
  in-code guard — audit the governance funding proposal).
- **Fail-soft** streamers: confirm `/monitoring` alerts on the `*_skipped_blocks` counters; model
  the economic impact of a prolonged silent skip.
- **Cosmos SDK module simulation** (`x/simulation`) across the 5 modules together.

### Track E — Economic / game-theoretic modeling  **[NEW — HARD launch blocker, ADR-008]**
Explicitly excluded from every prior report.
- Bonded-ratio dynamics on a **free / zero-price** chain (target 66% / floor 50% / red line 33%).
- **Reward gaming:** N minimum-bond validators each farming the `max(floor 10 GMB, …)` per-validator
  floor → drains the 20M reserve faster than the intended ~2M/yr and dilutes honest validators.
  Bound reserve-drain vs validator count (interacts with the inactive valgate caps, finding #3).
- Security-budget cliff (~year 10): cost-to-attack ≥ 3× value-secured; tail-reward handoff.
- Governance capture with ~90% supply non-voting (thin early electorate); vote-buying with free
  tokens; a **majority** malicious proposal actually executing end-to-end (prior tests only defeat
  a *minority* attacker).
- Fee-market base-fee manipulation under load; MEV / proposer ordering on the EVM side.

### Track D — Mainnet genesis config  **[NEW for mainnet — only testnet exercised, and it had a min-self-delegation bug]**
- **Dry-run the FULL mainnet genesis on a throwaway devnet** and diff every param vs the checklist.
- Assert: mint disabled + allocation reconciles to exactly 100,000,000; **reserve exclusion
  populated at genesis** (finding #3, #1 item); **valgate caps set** (finding #3); **min_gas_price
  > 0** (finding #3); gov params tightened (finding #3); unbonding 7–21d; genesis validators ≥ 4
  with no privilege; `--min-self-delegation` correct.
- Produce an **irreversible-at-genesis checklist** (supply, mint-off, allocation, exclusion set,
  gov/slashing params) with a signed reconciliation.

### Track F — Smart-contract adversarial depth  **[RE-VERIFY treasury/gov; NEW on DEX core / onramp / untested]**
Strong prior coverage on reserves/governance/GmbCollector; gaps elsewhere.
- **GembaSwap (UniV2 fork):** Foundry/Echidna K-invariant + flash-swap `uniswapV2Call` callback
  abuse; **diff the `=0.5.16` core against canonical UniV2** for introduced deviations; verify the
  `init code hash` in `GembaSwapLibrary.pairFor` matches deployed creation code.
- **Untested contracts:** `WGMB`, `LiquidityLocker` (time-lock bypass), `GembaNativePoolFactory`,
  `GembaForwarder`/meta-tx replay+relayer griefing, `WorkplaceCheckIn`.
- **SPOF owner keys:** `GembaOnRamp`, `GembaPayDispenser`, `GmbCollector`, `GembaFaucet`,
  `GembaSwapFactory.feeToSetter` — **verify production owners are governance/Timelock, not EOAs**
  (check deploy scripts / `REGENESIS-ADDRESSES-*`). OnRamp owner can drain the GMB pool & move the
  rate; confirm MiCA gate `publicSaleEnabled=false` on mainnet.
- Reserve **UUPS** storage-layout drift across upgrades; `initialize` front-running at deploy
  (must be atomic).
- **Two-tier governance** tier-classification bypass: post-propose `criticalTarget` mutation; a
  Critical action bundled with benign targets.
- Re-confirm reserves excluded from `GembaVotes` **at deploy** (LiveGov flagged the failure mode).
- Tools: extend Foundry invariant suite, add **Echidna/Medusa** property fuzzing + **Slither**.

### Track G — Infra / key management / RPC hardening  **[NEW — out of scope in all prior reports]**
- Validator **key custody** (tmkms / HSM / Vault — a mainnet checklist item still unchecked).
- The validator **auto-ops daemons** (`auto-unjail`, `auto-compound`) run with operator keys on the
  boxes — no adversarial test exists; review their key handling + failure modes.
- **RPC DoS depth** (on devnet, never prod): `eth_getLogs` unbounded-range exhaustion, large
  `eth_call` memory growth, WS/subscription abuse, txpool flooding, state-sync/snapshot attacks.
- **P2P:** eclipse / peer-flooding (investigate the unexplained `Gembavalik` peer from P-4).
- Edge hardening incl. the **new cax31 archive+explorer box** (localhost-only RPC, 26656-only
  public — per `target-architecture.md`); nginx/Cloudflare config.
- Secret-hygiene re-scan (the round-4 PAT rotation is still pending; the dev2 mnemonic recurred 3×).

### Track H — Backend services  **[NEW — only faucet + access-control audited]**
- `services/purchase-backend` (fronts the `GmbCollector` payment flow) — injection, authz,
  **webhook/settlement forgery** (the on-chain contract trusts off-chain settlement as authoritative).
- `services/blockchain-notifier`, `services/contact-form` — input handling, auth, SSRF/injection.

### Track I — Long-running / state-growth  **[NEW for security — perf harnesses exist but aren't security-scoped]**
- Validator-registration spam / state bloat (the min-self-bond floor bounds cost — measure it).
- Unbounded table growth (`access_logs`, `revocation_outbox`, capabilities).
- Pruning correctness over time on the pruned validator RPCs; EVM state growth; long-soak consensus
  stability. Cross-reference the `stress/` + `endurance/` harnesses for security-relevant findings.

---

## Methodology & tooling
- **Go:** `go test -fuzz`, property/invariant tests, Cosmos SDK `x/simulation`, differential tests
  vs a reference implementation for the reward math.
- **Solidity:** extend Foundry invariant/fuzz suites; **Echidna/Medusa** property fuzzing;
  **Slither** static; fork-tests against live state (`LiveGov.t.sol` pattern).
- **Live/dynamic:** extend `security/track3-rpc-infra/rpc-fuzz.js` toward resource-exhaustion +
  precompile probing — **on a throwaway devnet, never prod** (the `track2-consensus` devnet guard
  pattern: refuse to run unless it detects the devnet chain-id).
- **Destructive consensus / slashing / genesis dry-runs:** throwaway 4-node devnet (reuse
  `security/devnet/up.sh`), never the live chain.
- **External audit:** commission a specialist firm for Track C (upstream Cosmos EVM) + Track B
  (precompile boundary) + Track E (economic model) — the three declared/effective launch blockers.

## Priority & mainnet gating
- **P0 — must pass before genesis (launch blockers):** Track C (upstream EVM), Track B
  (native-denom-mint safety), Track E (economic security budget), Track D (genesis config —
  reserve exclusion, valgate caps, min_gas>0, gov hardening).
- **P1 — high:** Track A (module fuzz + the 3 concrete findings), Track F (DEX/onramp/untested +
  SPOF-owner verification), Track G (key custody + auto-ops daemons).
- **P2 — medium:** Track H (backend services), Track I (state growth), remaining infra depth.

## Deliverables
Per-track findings with severity + repro + fix, a re-run of the `security/` harness against the
final mainnet-candidate build, the signed irreversible-at-genesis reconciliation, and a go/no-go
memo tied to the two declared hard launch blockers (upstream EVM audit; tail-reward + bonded-ratio
monitoring live).
