# GembaBlockchain — Security Audit Report

**Date:** 2026-06-07
**Auditor:** Lead Security Auditor (multi-agent review + adversarial verification)
**Scope:** GembaBlockchain monorepo — chain Go modules, Solidity contracts, backend services, ops/secret hygiene
**Confirmed findings:** 10 (0 Critical, 0 High, 2 Medium, 7 Low, 1 Info) — severities reflect post-verification adjustment.

---

## 1. Executive summary

GembaBlockchain is, overall, in **solid security shape for its stage**. No critical or high-severity issues survived adversarial verification. There is **no finding involving fund loss, supply inflation, unauthorized minting, reserve drain, or a directly attacker-triggered consensus halt.** The custom chain modules preserve the project's hard supply invariant, the Solidity treasury/governance stack follows the documented secure-by-default standards (UUPS behind Timelock, reserves excluded from voting, CEI + `nonReentrant`), and the off-chain access-control service correctly keeps PII off-chain with row-level isolation.

The two **Medium** findings are both *defense-in-depth / liveness hardening gaps in the Go layer*, not exploitable economic attacks:

- An **anti-spam validator floor is bypassable via the EVM staking precompile** (downgraded from High to Medium — consensus is stake-weighted, so sub-floor validators have negligible power and there is no safety/economic break, but the §5.2 anti-spam *quality* guarantee is genuinely defeated).
- A **misconfigured `FaucetAccount` governance param can panic `BeginBlock` and brick the chain** (governance-gated behind supermajority + timelock, so not externally triggerable, but a foreseeable migration footgun the existing "fail-soft" was meant to prevent).

The remaining issues are Low/Info: standard AMM FoT semantics on third-party DEX reference code, operator-misconfiguration edges on the on-ramp, BeginBlock fail-soft inconsistency in two reward modules, an unprocessed GDPR retry outbox, and several valueless-testnet faucet/harness hardening notes (rate-limit bypass, nonce races, a well-known dev mnemonic, plaintext throwaway keys).

**Bottom line:** the codebase is largely sound and consistent with its own spec. The most valuable fixes are (a) enforcing the validator floor at the staking `MsgServer` layer so the EVM path is covered, and (b) making every `BeginBlock` panic/error fail-soft. Neither blocks devnet/testnet use; both should land before public mainnet, alongside the already-tracked hard blockers (upstream Cosmos EVM audit, security-budget tail).

---

## 2. Findings summary

| # | Severity | Component | Title |
|---|----------|-----------|-------|
| 1 | Medium | Chain Go modules (valgate/ante) | Min-self-bond floor bypassable via EVM staking precompile (`createValidator`) |
| 2 | Medium | Chain Go modules (feesplit) | Invalid `FaucetAccount` param panics `BeginBlock` → unrecoverable chain halt |
| 3 | Low | DEX (GembaNativePool) | Swaps not fee-on-transfer-aware on the output side; `amountOutMin` checked against gross output |
| 4 | Low | On-ramp (GembaOnRamp) | GMB payout computed from requested `stableIn`, not actually-received amount |
| 5 | Low | Chain Go modules (rewardstreamer, tailreward) | `BeginBlock` halts chain on any send error (inconsistent with feesplit fail-soft) |
| 6 | Low | Backend (access-control) | GDPR revocation outbox is write-only — failed on-chain revocations never retried |
| 7 | Low | Backend (testnet-faucet) | Address-based rate limit trivially bypassable; no global drain cap |
| 8 | Low | Backend (testnet-faucet) | Faucet wallet has no nonce serialization — concurrent drips can collide |
| 9 | Low | Secret hygiene (testnet) | Live testnet drip account keyed by well-known committed cosmos/evm dev mnemonic |
| 10 | Info | Harness (stress) | 300 worker private keys written to `wallets.json` in plaintext (no `chmod 600`) |

---

## 3. Findings in detail

### Finding 1 — Min-self-bond floor bypassable via the EVM staking precompile *(Medium)*

- **Component:** Chain Go modules (`x/valgate` ante decorator)
- **Location:** `chain/x/valgate/ante.go` (`MinSelfBondDecorator.AnteHandle` / `checkMsgs`); staking precompile activated by `evmd/genesis.go` (`ActiveStaticPrecompiles = AvailableStaticPrecompiles`, includes `StakingPrecompileAddress 0x…0800`).
- **Description:** The §5.2 anti-spam validator floor (genesis `valgate.min_self_bond = 1000 GMB`) is enforced **only** by the ante decorator, which inspects `tx.GetMsgs()` and type-asserts for `*MsgCreateValidator` / `*authz.MsgExec`. It correctly closes the authz `MsgExec` hole (prior finding #9), but an EVM transaction surfaces as `*MsgEthereumTx`, matching neither. The cosmos/evm staking precompile (`precompiles/staking/tx.go: CreateValidator`) builds a `MsgCreateValidator` and calls `stakingMsgServer.CreateValidator` **directly during EVM execution — after the ante phase**, with no `MinSelfBond` check anywhere in `precompiles/staking/`. Confirmed active in the live `gemba-validator/genesis.json`.
- **Impact:** Any EOA can `createValidator` via an EVM tx to `0x…0800` with `Value`/`MinSelfDelegation` of `1 agmb`, fully bypassing the 1000-GMB floor. At/near launch (4 genesis validators, `MaxValidators = 150`) a sub-floor validator enters the **active** set immediately. The permissionless-but-anti-spam guarantee in §5.2 is defeated. **Bounded:** consensus is stake-weighted, so such a validator has negligible voting/proposer power (cannot halt or forge), there is no fund loss, and stake-ranking still protects real validators once the set fills — hence Medium, not High. What is defeated is anti-spam quality control, not a safety/economic invariant.
- **Recommendation:** Do **not** rely on an ante decorator for this invariant on an EVM chain. Enforce the floor at the staking `MsgServer.CreateValidator` layer so both routes are covered: wrap `stakingkeeper`'s `MsgServer` to reject `Value.Amount < MinSelfBond` and `MinSelfDelegation < MinSelfBond`, construct the staking precompile with that wrapped server, and register it on the module's msg route. Keep the ante check as defense-in-depth. Add a test creating a validator through the precompile and asserting sub-floor rejection.

### Finding 2 — Invalid `FaucetAccount` param panics `BeginBlock` → chain halt *(Medium)*

- **Component:** Chain Go modules (`x/feesplit`)
- **Location:** `chain/x/feesplit/keeper/split.go:42` (`SendCoinsFromModuleToModule` → `params.FaucetAccount`); `chain/x/feesplit/keeper/abci.go:15`; `chain/x/feesplit/types/params.go:24-35` (`Validate`).
- **Description:** `SplitFees` treats `FaucetAccount` as a *module name* and passes it to `bankKeeper.SendCoinsFromModuleToModule`, which **panics** (does not return an error) when the recipient module account is unregistered (`cosmos-sdk@v0.54.3 x/bank/keeper/keeper.go:298-301`). `Params.Validate()` only checks `FaucetAccount != ""` (a stateless validator, no keeper access) — it cannot verify the name resolves to a registered module account. The `BeginBlock` "fail-soft" wrapper recovers only from **returned errors**, not panics. A governance `MsgUpdateParams` setting `FaucetAccount` to a typo, a bech32, or a `0x` contract address (explicitly anticipated by the `keys.go` "faucet becomes a Solidity contract" comment) passes validation, then panics every block → permanent halt until a coordinated binary/migration fix.
- **Impact:** A single accepted governance param change can permanently halt the chain, defeating the exact goal the fail-soft was added for. **Not externally exploitable:** `UpdateParams` is gated to the gov-module authority, and §7 routes such changes through supermajority + a long timelock that makes a malformed flip visible and blockable before execution. The default `faucet` module account is registered, so normal operation is fine. Hence Medium — a governance-gated liveness footgun, not an attack.
- **Recommendation:** Give the feesplit keeper an `AccountKeeper` and reject in `SetParams`/`UpdateParams` if the name is not a registered module account (or, for a contract/EOA recipient, resolve a bech32 address and use `SendCoinsFromModuleToAccount` with a blocked/existence pre-check). Additionally wrap the `BeginBlock` body in `defer`/`recover` so any unforeseen panic degrades to a skipped split rather than a halt.

### Finding 3 — GembaNativePool not FoT-aware on the output side *(Low)*

- **Component:** DEX (GembaSwap V2 / WGMB / NativePool / LiquidityLocker)
- **Location:** `contracts/src/dex/GembaNativePool.sol:161-174` (`swapExactNativeForTokens`), `:177-194` (`swapExactTokensForNative`).
- **Description:** The pool correctly sizes swaps from the `balanceOf` delta on the **input** side (FoT-safe, lines 115-118 / 186-189). On the **output** side it computes `amountOut`, checks it against `amountOutMin` *before* `token.safeTransfer(to, amountOut)`. For a fee-on-transfer output token the recipient receives less than the gross `amountOut` that already passed the min-out check. There is no `...SupportingFeeOnTransferTokens` variant.
- **Impact:** A user swapping for an FoT output token can receive less than their stated `amountOutMin` — self-inflicted slippage only. **No pool drain:** `reserveToken` is decremented by exactly the `amountOut` paid out, so K is preserved regardless of the token's transfer fee. This is identical to standard (non-supporting) Uniswap V2 semantics, and the contract is third-party, non-project-operated developer reference infra. FoT output tokens are exotic.
- **Recommendation:** Document in NatSpec (next to `getAmountOut`) that the pool targets standard non-FoT tokens, or add an FoT-aware output path measuring the recipient's `balanceOf` delta.

### Finding 4 — OnRamp computes GMB payout from requested `stableIn`, not received amount *(Low)*

- **Component:** On-ramp (`GembaOnRamp`)
- **Location:** `contracts/src/onramp/GembaOnRamp.sol:buy` (lines 76, 82).
- **Description:** `buy()` computes `gmbOut = stableIn * rate / 1e18` then pulls `stableIn` via `safeTransferFrom`, without measuring the actual received balance delta. A fee-on-transfer/rebasing stablecoin would deliver less than `stableIn` while GMB is still priced on the full `stableIn`.
- **Impact:** Under-collection of stablecoin / slow GMB-pool over-payment proportional to the transfer fee — **only** if an FoT stablecoin is selected. The stablecoin is immutable and operator-chosen, the documented intent is a standard USD stablecoin (USDC/USDT, zero fee), `publicSaleEnabled` is false by default (behind a MiCA sign-off), and the owner already has full custody (`withdrawStable`/`withdrawGmb`). Selecting an FoT token is operator self-harm bounded by the fee percentage, not third-party theft.
- **Recommendation:** Compute `gmbOut` from the measured balance-before/after delta, or explicitly require/document a standard non-FoT, non-rebasing ERC-20.

### Finding 5 — rewardstreamer / tailreward `BeginBlock` halt on send error *(Low)*

- **Component:** Chain Go modules (`x/rewardstreamer`, `x/tailreward`)
- **Location:** `chain/x/rewardstreamer/keeper/abci.go:15-18`, `chain/x/tailreward/keeper/abci.go:13-16` (`return err`) vs `chain/x/feesplit/keeper/abci.go` (logs, returns nil).
- **Description:** feesplit was deliberately made fail-soft (comment cites "audit finding #5": a returned `BeginBlock` error is fatal to consensus). Both reward modules instead propagate any error from `StreamRewards`/`StreamTailReward`, which halts the node in `FinalizeBlock` — the exact outcome feesplit was changed to avoid. Self-inconsistent robustness defect.
- **Impact:** **Not attacker-exploitable** — the send is module→module to the always-registered `fee_collector`, available balance is pre-checked, `amount = min(perBlock, available)`, no `SendRestriction` hook is registered, and module→module bypasses blocked-address checks. The residual risk is a future upstream `SendRestriction` or unexpected bank error halting the chain instead of harmlessly skipping one block's reward (supply-safe to skip). Severe-but-near-zero-likelihood.
- **Recommendation:** Apply the feesplit treatment: log and skip the reward on error, plus a `defer`/`recover`, so the reward stream can never halt consensus.

### Finding 6 — GDPR revocation outbox is write-only *(Low)*

- **Component:** Backend (access-control)
- **Location:** `services/access-control/src/gdpr.js:48-54` (`eraseEmployee`) + `src/db.js:129-134` (`recordFailedRevocation`); table `db/schema.sql:69-77` (`revocation_outbox.retried_at`).
- **Description:** During GDPR erasure, PII is deleted first, then on-chain capability tokens are revoked best-effort. On `chain.revokeAccess` failure (RPC down, nonce/gas) the failure is written to `revocation_outbox` "to be retried later" — but **no code reads or processes that table**; `retried_at` is never updated. The promised retry path does not exist.
- **Impact:** After erasure, if the RPC was unavailable, the on-chain capability NFT may remain unrevoked, retaining physical access until a manual fix. **Mitigated:** `eraseEmployee` returns a per-cap `{ok:false, error}` array sent synchronously in the DELETE HTTP response (the institution is told immediately which revocations failed); the outbox durably stores `wallet + zone + reason` for manual re-issue; it fires only on operational RPC failure (not adversary-controlled); and the legal GDPR obligation (PII deletion) succeeds independently first — the stale token is already de-identified. An eventual-consistency / incomplete-feature gap, not a directly exploitable vuln.
- **Recommendation:** Add a worker/cron selecting `revocation_outbox` rows where `retried_at IS NULL` (or past a backoff), calling `chain.revokeAccess` and setting `retried_at`/deleting on success. Add a metric/alert on outbox depth and age.

### Finding 7 — Faucet rate limit bypassable; no global drain cap *(Low)*

- **Component:** Backend (testnet-faucet)
- **Location:** `services/testnet-faucet/src/server.js:37-63` (`/drip`) + `src/ratelimit.js` (`CooldownLimiter`).
- **Description:** Per-recipient-address cooldown is defeated by generating a fresh recipient address per request (free), leaving only a per-IP 24h cooldown. The limiter is in-memory (resets on restart, not shared/durable), and there is no per-day global budget or low-balance circuit-breaker. The `ratelimit.js` docstring's claim that a single requester "can't drain the drip account" is contradicted by the address bypass.
- **Impact:** An actor with many IPs (proxies/botnet) or a process restart can drain the drip account faster than intended. **Valueless testnet tokens**, in-memory limitation is documented — blast radius is operational (faucet runs dry), no financial/consensus impact.
- **Recommendation:** Back the limiter with a shared durable TTL store (Redis), add a global daily drip budget and a minimum-balance guard, and consider lightweight PoW/captcha to raise per-request cost.

### Finding 8 — Faucet wallet has no nonce serialization *(Low)*

- **Component:** Backend (testnet-faucet)
- **Location:** `services/testnet-faucet/src/faucet.js:22-28` (`drip`), `server.js /drip`.
- **Description:** `drip()` calls `wallet.sendTransaction` with no nonce management; the plain `ethers.Wallet` auto-fetches the `pending` nonce. Concurrent drips to different addresses/IPs (allowed past the cooldown checks) can read the same nonce before either is mined, so one tx is replaced/rejected.
- **Impact:** Liveness/UX only — the entitled requester gets a drip-failed error, but `server.js` rolls back the cooldown so they can retry immediately. No fund loss, no double-spend; valueless testnet.
- **Recommendation:** Serialize sends through a single in-process queue, or track/pass an explicit incrementing nonce.

### Finding 9 — Live testnet drip account keyed by well-known committed mnemonic *(Low)*

- **Component:** Secret hygiene (testnet)
- **Location:** `chain/testnet/testnet.params.sh:18-20` (`TN_FAUCET_MNEMONIC` / `TN_FAUCET_ADDR_0X`), used by `chain/testnet/init-local-testnet.sh:35`.
- **Description:** The live drip account (`0x40a0cb1C…eFa9`, allocated 2,000,000 test GMB — confirmed in `docs/testnet-deployments.md:56`) is recovered from the publicly-known cosmos/evm `dev2` mnemonic, committed in-repo and published upstream. Because the funded on-chain account itself derives from a public mnemonic, anyone can sign from it — independent of the service correctly reading `FAUCET_KEY` from env.
- **Impact:** On the live `gemba-testnet-1`, an attacker can sweep/grief the 2M test-GMB drip account, taking the faucet offline (DoS to onboarding/dev users). **Valueless by design; no monetary loss; not a mainnet/§3 secrets violation** (the file warns "Never reuse mainnet keys here"). Bounded, recoverable availability disruption.
- **Recommendation:** Fund the live testnet drip account from a freshly-generated keypair whose mnemonic stays in the operator secret store/env. Keep the well-known `dev2` key only for ephemeral local bootstrap, and document that the live drip address differs.

### Finding 10 — Stress harness writes 300 worker private keys in plaintext *(Info)*

- **Component:** Harness (stress)
- **Location:** `stress/lib/wallets.js:6-14` (`generateWallets`), `stress/scripts/00-gen-wallets.js`.
- **Description:** `generateWallets()` persists freshly-generated worker private keys to `wallets.json` via `writeFileSync` with default permissions (no `chmod 600`). The file is gitignored and the keys are throwaway, low-balance (`FUND_PER_WALLET = 2.0`) testnet keys.
- **Impact:** On a shared/multi-user host, other local users could read the keys (umask-dependent). Valueless testnet GMB, no repo/mainnet exposure — purely a local hardening note.
- **Recommendation:** Optionally write with mode `0o600` and document that the file must never leave the host. No change needed if the harness only ever runs on a single-operator box.

---

## 4. What's solid

Observed strengths (genuinely verified during review):

- **Supply invariant holds.** rewardstreamer, tailreward and feesplit are all transfers of pre-existing coins — no mint path; skipping a stream is supply-safe. Zero-inflation design is intact in code.
- **Treasury/contract upgrades are properly gated.** UUPS reserves are upgradeable only via Governor + Timelock (no EOA upgrade authority), the Governor excludes reserve-holding contracts from `getVotes`, and `EmergencyPause` is pause-only (cannot move funds) — matching §7/§9.
- **Solidity secure-by-default standards are followed.** CEI + `nonReentrant` on value/external-call paths, custom errors with zero-address/zero-amount/bounds checks, and events on state changes across the DEX, on-ramp, tickets/perks and access contracts.
- **AMM accounting is sound.** GembaNativePool decrements reserves by exactly the amount paid out, preserving K; the input side is correctly FoT-safe via balance deltas.
- **PII stays off-chain with real isolation.** The access-control service uses PostgreSQL `FORCE` RLS to isolate each institution's identity rows, and GDPR erasure deletes PII independently of (and before) on-chain revocation — consistent with §10.
- **Validator-floor authz hole is closed.** The ante decorator correctly unwraps `authz.MsgExec` (prior finding #9); the remaining gap is only the separate EVM precompile route (Finding 1).
- **Secret hygiene on the service layer is correct.** The faucet service reads `FAUCET_KEY` from env (not committed); the one exposed key (Finding 9) is a documented valueless testnet dev key, and harness keys (Finding 10) are gitignored throwaways.
- **Defensive intent is present.** feesplit already implements fail-soft `BeginBlock`; the inconsistency (Findings 2, 5) is incomplete propagation of that good pattern, not its absence.

No critical/high issue, no fund-loss path, and no attacker-triggered consensus break survived verification.

---

## 5. Scope & method

- **Method:** Multi-agent review with an **adversarial verification pass** — every candidate finding was re-checked against source (and dependency code, e.g. `cosmos-sdk@v0.54.3` bank keeper, cosmos/evm `precompiles/staking`) to confirm exploitability and right-size severity. Several initial ratings were **downgraded** on verification (e.g. validator-floor bypass High→Medium; GDPR outbox Medium→Low), and unverifiable/refuted candidates were dropped. Only the 10 confirmed findings above are reported.
- **Covered:** custom chain Go modules (`valgate`/ante, feesplit, rewardstreamer, tailreward) and their genesis/wiring; Solidity DEX, on-ramp, tickets/perks, treasury/governance, access contracts; backend services (access-control, testnet-faucet); stress harness; secret hygiene and committed config.
- **Not covered / out of scope (tracked elsewhere as hard launch blockers):** the upstream **Cosmos EVM pre-v1 audit** (ADR-006) and the **long-term security-budget tail** review (ADR-008) remain the founder's separate, non-code launch gates and were not re-assessed here. No live-network penetration testing, no formal verification, and no economic/game-theoretic simulation of validator/governance incentives were performed. This review is a point-in-time source audit, not a guarantee of absence of all defects.
