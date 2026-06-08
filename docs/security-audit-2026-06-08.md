# GembaBlockchain — Security Audit Report

**Date:** 2026-06-07
**Auditor:** Lead Security Auditor (multi-agent review + adversarial verification)
**Scope:** GembaBlockchain monorepo — Cosmos Go modules, Solidity contracts, backend services
**Repository:** `/home/slavy/GembaBlockchain` (branch `main`)

---

## 1. Executive Summary

GembaBlockchain is in **good security health**. The audit, after adversarial re-verification of every candidate issue, surfaced **no critical or high-severity vulnerabilities** — no fund-draining exploit reachable by an unauthenticated attacker, no consensus break, no privilege-escalation path, and no violation of the chain's core economic invariants (fixed supply, zero inflation, reserves-never-vote held in practice).

The confirmed findings are **3 medium** and **9 low** severity. None are launch blockers in the sense of the project's own §16 hard gates (upstream Cosmos EVM audit; tail-reward + bonded-ratio monitoring), but several should be fixed before a public mainnet launch.

The themes are consistent and unsurprising for a system at this maturity:

- **Operational robustness gaps in backend services** (the access-control API and testnet faucet) — blocking RPC calls inside DB transactions, a spoofable rate limiter, GDPR erasure that aborts on a transient chain error. These are the highest-impact real issues and all live off-consensus.
- **Spec-vs-code drift** — controls described in docs/comments as existing (a Faucet "rate-limited tap," "governance-tunable" chain params, "reserves explicitly excluded" from voting) that are not actually wired up. The protections largely hold *structurally*, but the documented enforcement is missing, which is both a hardening gap and a maintenance hazard.
- **Reference-DEX hardening** — the non-project-operated `GembaNativePool` deviates from the bundled Uniswap V2 in ways that break on exotic tokens. Blast radius is one opt-in pool per token, never the shared DEX.

Notably, the most alarming-sounding candidate findings were **downgraded after verification** rather than confirmed at face value (e.g. the Faucet drain requires a *compromised privileged key*, not a public call; the reserve-voting gap is redundant with structural protections). The report below reflects those honest, adjusted severities.

---

## 2. Findings Summary

| # | Severity | Component | Title |
|---|----------|-----------|-------|
| 1 | Medium | Backend (access-control) | Blockchain calls inside open Postgres/RLS transaction — pool-exhaustion DoS + state inconsistency |
| 2 | Medium | Backend (access-control) | GDPR erasure aborts entirely if any on-chain revoke fails |
| 3 | Medium | Reserves (Faucet) | Per-grant cap is per-call only — compromised granter key can drain the faucet |
| 4 | Low | Backend (testnet-faucet) | Per-IP rate limit bypassable via `X-Forwarded-For` spoofing |
| 5 | Low | Chain Go modules | feesplit/rewardstreamer/tailreward params not governance-tunable (no `MsgUpdateParams`) |
| 6 | Low | Tickets/Perks | `buy()` lets the public mint price-0 ("not for sale") events for free |
| 7 | Low | DEX (NativePool) | Silent break on fee-on-transfer/rebasing tokens — locked LP withdrawals |
| 8 | Low | DEX (NativePool) | `to` recipient not validated — native GMB can be burned to `address(0)` |
| 9 | Low | Chain Go modules (valgate) | Min-self-bond ante floor bypassable via authz `MsgExec` nesting |
| 10 | Low | Governance (Votes) | Reserve contracts never added to `GembaVotes` exclusion set at deployment |
| 11 | Low | Backend (testnet-faucet) | In-memory cooldown limiter — unbounded growth, lost on restart, not shared |
| 12 | Low | Backend (both services) | Error handlers return raw internal error messages to clients |

---

## 3. Detailed Findings

### Finding 1 — Blockchain calls execute inside the open Postgres (RLS) transaction
**Severity:** Medium · **Component:** Backend services (access-control)
**Location:** `services/access-control/src/app.js:48-58` (POST `/capabilities`); `src/gdpr.js:22-38` via `app.js:79-85` (DELETE `/employees/:id`); inside `db.withTenant` (`src/db.js:18-32`).

**Description.** `withTenant` opens a transaction (`BEGIN` + `SET LOCAL app.current_tenant`) and holds a pooled connection for the entire callback. POST `/capabilities` calls `chain.grantAccess(...)` which awaits `tx.wait()` (`chain.js:21-22`) — blocking for a full block confirmation (~2 s+) while the Postgres transaction sits *idle in transaction*. The GDPR erase path does the same, one `revokeAccess` per capability. With pg's default pool (`max 10`), roughly 10 concurrent capability/erase requests exhaust the pool and stall **all** tenants. Mixing the external call inside the transaction also breaks atomicity: if the chain call succeeds but the subsequent `COMMIT` fails, on-chain and off-chain state diverge (orphan NFT, or access revoked while PII remains).

**Impact.** A valid tenant can hold DB connections open for seconds each, exhausting the shared pool and causing a cross-tenant denial of service. Confirmation failures after the chain call leave on-/off-chain state inconsistent. (Row-lock concern from the original report is minor — the `SELECT` has no `FOR UPDATE` and the `INSERT` runs after the wait; the binding issue is the idle connection.)

**Recommendation.** Never perform RPC/`tx.wait()` inside the DB transaction. Restructure to: (1) read needed data in a short tenant-scoped transaction; (2) perform the on-chain call outside any transaction; (3) record the result in a second short transaction. Add an outbox/idempotency record so a crash mid-flow is recoverable, treating the on-chain mint/revoke as the reconciliation source of truth.

---

### Finding 2 — GDPR erasure aborts entirely if any on-chain revoke fails
**Severity:** Medium · **Component:** Backend services (access-control)
**Location:** `services/access-control/src/gdpr.js:26-37` (`eraseEmployee` revoke loop).

**Description.** `eraseEmployee` revokes each on-chain capability **before** deleting off-chain PII. The loop has no `try/catch` (the "best-effort … never swallow silently" comment is misleading — it neither catches nor continues). If any `chain.revokeAccess` throws (transient RPC outage, gas issue, already-revoked token), the exception propagates, `db.deleteEmployee` is never reached, and the whole `withTenant` transaction rolls back. The off-chain PII — the legally significant data under the GDPR right to erasure (CLAUDE.md §10) — is therefore **not** deleted whenever the chain is unavailable. The live endpoint (`app.js:81-82`) calls `eraseEmployee` with `revokeOnChain` defaulting to `true`, so the off-chain-only path is unreachable. This contradicts the file's own documented intent (header lines 6-10): revocation is "optional" and deleting off-chain PII alone satisfies erasure. The already-revoked revert can permanently deadlock erasure on retry, not just transiently.

**Impact.** A transient blockchain/RPC failure indefinitely blocks erasure of personal data — the part that matters for GDPR compliance. On-chain revocation may also be left partial on the failing iteration.

**Recommendation.** Decouple ordering: always delete off-chain PII (the erasure obligation) first/independently, then attempt on-chain revocation as a separate, retryable best-effort step (record failures to an outbox). Wrap per-capability revokes so one failure doesn't abort the others, and make the on-chain calls idempotent (tolerate already-revoked).

---

### Finding 3 — Faucet per-grant cap is per-call only; compromised granter can drain the reserve
**Severity:** Medium · **Component:** Reserves (Faucet)
**Location:** `contracts/src/reserves/Faucet.sol:46-52` (`grant()`), `perGrantCap` field (line 25); deploy value `DeployGovernance.s.sol:29`.

**Description.** `grant()` enforces only `if (amount > perGrantCap) revert AboveCap();` — a single-transaction cap (1000 ether at deploy). There is no per-epoch/per-time/cumulative outflow limit anywhere in `Faucet` or `BaseReserve`; `totalGranted` is incremented but never compared to any budget (telemetry only). No vesting/streaming exists despite CLAUDE.md §6 describing grants that "drip over time." The contract NatSpec calls itself the "routine, rate-limited tap" (lines 15, 44), a rate limit the implementation does not provide. The granter is explicitly a hot "formula/automation actor"; that key (or anyone who compromises it) can loop `grant()` with each call ≤ `perGrantCap` and drain the full 30M GMB (≈30,000 calls), bounded only by post-hoc detection + `setGranter` revoke or `EmergencyPause`.

**Impact.** Full drain of the 30% public/municipal reserve via a compromised or malicious **granter key** (not an unauthenticated public call — `grant()` is access-controlled). The documented "govern the tap rate" control does not actually bound flow rate; no §16 ADR records this as an accepted trade-off.

**Recommendation.** Add a genuine rate limit: a governance-tunable per-window budget (e.g. `maxPerEpoch` with a rolling/reset window) checked and accumulated in `grant()`, reverting when exceeded. This bounds the blast radius of a granter-key compromise to one window and makes the "govern the tap" invariant real.

---

### Finding 4 — Faucet per-IP rate limit bypassable via `X-Forwarded-For` spoofing
**Severity:** Low · **Component:** Backend services (testnet-faucet)
**Location:** `services/testnet-faucet/src/server.js:23,38` (`app.set('trust proxy', true)`; `ip = req.ip`).

**Description.** The faucet relies on a per-address limiter (useless against drain — attackers mint unlimited fresh EVM addresses) and a per-IP cooldown (the only meaningful defense). `trust proxy = true` makes Express set `req.ip` to the left-most, client-supplied `X-Forwarded-For` value. An attacker sends a random `X-Forwarded-For` per request (even hitting the service directly) and gets a unique `req.ip` each time, defeating the per-IP cooldown and contradicting the stated goal in `ratelimit.js:2-3`.

**Impact.** The `gemba-testnet-1` drip account can be drained, denying testnet onboarding. Tokens are **valueless** (testnet), so this is availability/DoS, not financial loss; the documented Apache reverse proxy front-end partially mitigates real-world exploitation by throttling on the true TCP source.

**Recommendation.** Set `trust proxy` to the exact number of trusted proxy hops (e.g. `1`) so `req.ip` is the real upstream peer. Run only behind the documented reverse proxy. Add a global drip budget / balance-floor circuit breaker, and consider PoW/captcha on the public endpoint.

---

### Finding 5 — feesplit / rewardstreamer / tailreward params are not governance-tunable
**Severity:** Low · **Component:** Chain Go modules
**Location:** `chain/x/feesplit/module.go`, `chain/x/rewardstreamer/module.go`, `chain/x/tailreward/module.go` (empty `RegisterServices`); no `MsgUpdateParams` / no param `Subspace` in these three modules.

**Description.** Only `x/valgate` exposes a `MsgServer` with `UpdateParams`. The other three store params in a private JSON KVStore (not `x/params`), have empty `RegisterServices` stubs, no authority field, and no `MsgUpdateParams` proto — so there is no on-chain path to change them after genesis. Yet `feesplit/params.go` and `rewardstreamer/params.go` say "governance-tunable," `tailreward` ships `Enabled=false, AnnualReward=0` "dormant until governance activates it," and CLAUDE.md §16.8/ADR-008 designates the tail reward a hard launch blocker and a runtime governance lever. Governance therefore cannot enable/size the tail reward or change the 40% fee split without a coordinated binary/genesis upgrade.

**Impact.** The §16.8/ADR-008 post-reserve security-budget lever cannot be activated or tuned by an on-chain gov tx. Mitigating context keeps this low: CLAUDE.md §7 explicitly sanctions coordinated node-operator upgrades for chain-binary/Go-module changes, the tail reward targets ~year-10 reserve depletion with months-to-years of bonded-ratio alerting lead time, and the 40% split is correct and active from genesis. This is a spec-vs-code discrepancy and a missing capability, not an exploitable hole.

**Recommendation.** Add a gov-authority-gated `MsgUpdateParams` `MsgServer` to all three modules (mirror `x/valgate/keeper/msg_server.go`): store `authAddr` in the keeper, check `msg.Authority == authority`, call `SetParams`; wire `RegisterServices` and pass `authAddr` in `NewKeeper`. Until then, correct the "governance-tunable" comments and CLAUDE.md to state these are genesis/upgrade-only.

---

### Finding 6 — Ticketing `buy()` lets the public mint price-0 ("not for sale") events for free
**Severity:** Low · **Component:** On-ramp + Tickets/Perks
**Location:** `contracts/src/tickets/GembaTicketing.sol` — `buy()` (lines 82-93), struct comment (line 23), `createEvent` (lines 58-63).

**Description.** `EventInfo.price` documents `0 = not for sale`, but `createEvent` permits `price==0` and forces `active=true`. `buy()` computes `cost = e.price * amount` (= 0), checks only `msg.value == cost`, and has no access control. Any caller can `buy(eventId, maxSupply)` with `msg.value == 0` and mint the entire supply of a comp/perk event for free. Because `minted` is never decremented (redeem burns but doesn't reduce `minted`), supply is permanently exhausted, and `GembaPerks.grantPerk → issue()` then reverts `ExceedsSupply`, defeating the documented perk flow. Deactivating via `setEventActive(false)` is not atomic with `createEvent`, leaving a front-run window.

**Impact.** Pure griefing/DoS with **no value at stake** (tickets are free). An attacker can front-run an organizer and squat all tickets of a price-0 event, denying legitimate recipients and undermining the Perks flow. Organizers have trivial workarounds (nonzero price, deactivate, fresh `eventId`).

**Recommendation.** In `buy()`, revert when `e.price == 0` (e.g. `NotForSale` custom error), making price-0 events issue-only per the documented semantics. Optionally default new events to `active=false`.

---

### Finding 7 — `GembaNativePool` silently breaks for fee-on-transfer / rebasing tokens
**Severity:** Low · **Component:** DEX (NativePool)
**Location:** `contracts/src/dex/GembaNativePool.sol` — `addLiquidity` (L115-116), `swapExactTokensForNative` (L172-173); payout paths `removeLiquidity` (L132,140), `swapExactNativeForTokens` (L155,158).

**Description.** Unlike the bundled Uniswap V2 `GembaSwapPair` (which syncs reserves from `balanceOf`, making it FoT-safe), `GembaNativePool` tracks `reserveToken` with pure internal accounting and credits the full nominal `amount`/`amountIn` immediately after `safeTransferFrom`. For a fee-on-transfer or rebasing token the contract receives less than credited, so `reserveToken` drifts above the real ERC-20 balance. Later `removeLiquidity`/`swapExactNativeForTokens` compute payouts from the inflated reserve that exceed the real balance, so `safeTransfer` reverts. The `MINIMUM_LIQUIDITY` lock prevents a 100% drain but the revert is reachable for non-trivial fees. The NativePool docstring claims "Follows docs/security-standards.md," and `test/Dex.t.sol` exercises FoT only against the router, never the NativePool.

**Impact.** In any opt-in pool created for a FoT/rebasing token, later removals/swaps revert (DoS) and the token side of LP funds is effectively locked. No theft, no attacker-controlled drain of others. Per CLAUDE.md §9 these are permissionless, opt-in, third-party-deployed reference contracts (not project-operated); blast radius is one self-inflicted pool per exotic token.

**Recommendation.** Either (a) measure actually-received amounts via `balanceOf` before/after (as the Uniswap pair and `LiquidityLocker.lock` already do) and size reserves/LP/output from the deltas; or (b) explicitly reject non-standard tokens and document loudly in NatSpec + README that NativePool does not support FoT/rebasing tokens, adding a FoT test asserting the revert.

---

### Finding 8 — `GembaNativePool` does not validate the `to` recipient
**Severity:** Low · **Component:** DEX (NativePool)
**Location:** `contracts/src/dex/GembaNativePool.sol` — `removeLiquidity` (L141, `_sendNative`), `swapExactTokensForNative` (L174); `_sendNative` (L77-80).

**Description.** `security-standards.md` §3 mandates zero-address checks on external inputs at function start. `_sendNative` uses `call{value:}` and only reverts on `!ok`; a transfer to `address(0)` returns `ok == true`, silently burning native GMB. Two native-out paths lack a `to` check: `removeLiquidity` and `swapExactTokensForNative`. (The original report also cited `swapExactNativeForTokens`/`addLiquidity`, but those pay out via OZ `safeTransfer`/`_mint`, which revert on `address(0)` — not exploitable.)

**Impact.** A caller (or buggy integrating contract) passing `to == address(0)` on a native-out path loses their own native GMB with no revert. Self-inflicted, caller-funds only, no privilege/third-party impact; mirrors stock Uniswap V2's omission. A fail-loud foot-gun, not an exploit.

**Recommendation.** Add `if (to == address(0)) revert ZeroAddress();` at the start of `removeLiquidity` and `swapExactTokensForNative` (and, for consistency, the other entrypoints), per §3.

---

### Finding 9 — Min-self-bond ante floor bypassable via authz `MsgExec` nesting
**Severity:** Low · **Component:** Chain Go modules (valgate)
**Location:** `chain/x/valgate/ante.go:24-34` (`MinSelfBondDecorator.AnteHandle`).

**Description.** The decorator iterates only top-level `tx.GetMsgs()` and type-asserts `*stakingtypes.MsgCreateValidator`; it does not unwrap nested messages. authz `DispatchActions` routes inner messages through the msg router **after** the ante phase (the canonical Cosmos pitfall). authz is enabled in the app and `MsgCreateValidator` has no authz blocklist, so an attacker self-grants (controlling both granter and grantee) and submits a `MsgCreateValidator` nested in `MsgExec`, evading the §5.2 self-bond floor. The valgate decorator is the sole min-self-bond check (staking's `MinSelfDelegation` is validator-self-set). `ante_test.go` only covers direct, non-nested txs.

**Impact.** Validators can be created below the governance-set minimum self-bond (launch 1,000 GMB), defeating the anti-spam floor. Bounded: the floor is deliberately tiny (~0.001% of supply), active-set entry remains stake-ranked (`MaxValidators` 150), and each creation still costs gas. Realistic harm is cheap validator-object registration spam / state bloat — no consensus-power gain, no fund risk.

**Recommendation.** Recursively unwrap authz `MsgExec` inner messages in `AnteHandle` before the `CreateValidator` check (flatten nested sdk messages), and add a test nesting `MsgCreateValidator` in `MsgExec` asserting rejection below the floor.

---

### Finding 10 — Reserve contracts never added to `GembaVotes` exclusion set at deployment
**Severity:** Low · **Component:** Governance (Votes)
**Location:** `contracts/script/DeployGovernance.s.sol` (`run`, lines 31-86); `contracts/src/governance/GembaVotes.sol` (`setExcluded`, `excluded` mapping).

**Description.** The "reserves never vote" invariant (§3.4/§7) is implemented in `GembaVotes` via the `excluded[]` mapping, but `DeployGovernance.s.sol` deploys the four reserve proxies and never calls `votes.setExcluded(...)` for any of them — so `excluded[]` is empty at genesis (`setExcluded` appears only in tests). The invariant nonetheless holds **structurally**: `BaseReserve`/reserve contracts have no code path that calls `GembaVotes.depositFor` or `delegate()`, so they cannot wrap native GMB into vGMB or acquire delegated voting power, and `ERC20Votes` requires explicit self-delegation (a stray vGMB transfer yields `getVotes == 0`). The documented explicit enforcement is simply not wired to the addresses it protects.

**Impact.** Defense-in-depth is absent at launch. The only impact scenario — a future UUPS upgrade adding a `depositFor`/`delegate` path — is itself gated by `_authorizeUpgrade onlyOwner == Timelock == full Governor flow`, which also controls `setExcluded` (and could reverse it), so genesis-populating the set is a redundant, reversible hardening step rather than a real defense against rogue governance. Spec-conformance gap, not an exploitable issue.

**Recommendation.** In `DeployGovernance.s.sol`, exclude every reserve/treasury address (and the Timelock/Governor) after deployment — either via a temporary deployer-as-governance window or a genesis governance proposal. Add a test asserting each reserve address is excluded.

---

### Finding 11 — In-memory cooldown limiter: unbounded growth, lost on restart, not shared
**Severity:** Low · **Component:** Backend services (testnet-faucet)
**Location:** `services/testnet-faucet/src/ratelimit.js:5-30` (`CooldownLimiter._last` Map); used in `server.js:17-18`.

**Description.** `_last` is only ever shrunk by `release()` (called solely on a failed send, `server.js:51-54`), so successful drips leave entries permanently; state is purely in-process (no persistence/sharing). Entries persist only after a successful 100-GMB drip, so reaching OOM-relevant counts would require ~1M successful drips draining ~100M GMB — the finite drip balance empties long before memory matters, making the "memory DoS" largely theoretical (the real binding failure is faucet drainage, Finding 4). Lost-on-restart and not-shared-across-instances are accurate but, on a deliberately simple single-instance testnet drip of valueless tokens, only let someone re-request valueless GMB.

**Impact.** Minor robustness weakness on a valueless-asset service. Cooldowns reset on deploy/restart and rate limiting is ineffective if more than one instance runs.

**Recommendation.** Evict expired keys (periodic sweep or check-and-delete when `remaining()==0`), or use a bounded LRU. For real deployments, back the limiter with a shared TTL store (Redis) so it survives restarts and works across instances.

---

### Finding 12 — Error handlers return raw internal error messages to clients
**Severity:** Low · **Component:** Backend services (both)
**Location:** `services/access-control/src/app.js:88-91`; `services/testnet-faucet/src/server.js:61-63`.

**Description.** Both global error handlers serialize `err.message` directly for 500-level errors. Internal errors — pg constraint/column/relation names, ethers/RPC errors including the configured RPC URL (`TESTNET_EVM_RPC`) — leak to callers unconditionally (no `NODE_ENV` gate, allowlist, or scrubbing). The `ValidationError` layer only covers intentional 4xx.

**Impact.** Information disclosure aiding reconnaissance; not directly exploitable. No auth bypass and no RLS escape (RLS enforced independently in `db.js`); these are testnet/devnet services.

**Recommendation.** For 5xx, log the full error server-side and return a generic message plus an error id to the client. Keep specific messages only for intentional 4xx `ValidationError` cases.

---

## 4. What's Solid

These strengths were observed and verified, and materially contribute to the low overall risk:

- **UUPS upgrades are gated by Governor + Timelock, never an EOA.** `_authorizeUpgrade` is `onlyOwner == Timelock`, so reserve/treasury contract upgrades require the full propose → vote → timelock → execute flow. This is why several "future upgrade could…" scenarios stay theoretical.
- **Supply invariant holds.** Fixed-supply / zero-inflation is preserved: rewards stream from a pre-minted reserve, the tail reward is recirculation-funded (no mint), and the chain modules contain no post-genesis minting path. Supply-constant behavior is tested.
- **"Reserves never vote" holds structurally,** independent of the missing exclusion wiring (Finding 10): reserves have no `depositFor`/`delegate` path and `ERC20Votes` requires explicit self-delegation.
- **Postgres RLS isolation is real and `FORCE`d.** Each tenant's identity rows are isolated by row-level security enforced in `db.js`, independent of the (devnet-placeholder) tenant header; the error-message leak (Finding 12) does not breach it.
- **Solidity contracts follow the project security standards** broadly — CEI + `nonReentrant` on value/external-call paths, custom errors, events on state changes, `SafeERC20`. The bundled GembaSwap is a faithful Uniswap V2 (FoT-safe pair); the deviations are confined to the custom `GembaNativePool`.
- **Access control is correct where it matters.** Faucet `grant()`, valgate param updates, and EmergencyPause (pause-only, governance-replaceable signers) are properly gated; the confirmed Faucet risk (Finding 3) requires compromising a *privileged* key, not a public call.
- **No critical/high findings.** Adversarial verification *downgraded* the scariest candidates rather than confirming them — a sign the design's structural protections are doing real work.

---

## 5. Scope & Method

**Method.** Multi-agent static review across the monorepo, followed by **adversarial verification** of every candidate finding: each was re-checked against the actual source, tests, and CLAUDE.md design intent, and either confirmed (with severity adjusted up or down to match real exploitability) or discarded. Only findings that survived this second pass are reported here; severities in this report are the *adjusted* (post-verification) severities, which in several cases are lower than first reported.

**Covered.** Cosmos Go modules (`x/valgate`, `x/feesplit`, `x/rewardstreamer`, `x/tailreward`, ante handlers) and app wiring; Solidity contracts (governance, reserves, tickets/perks, paymaster, on-ramp, the reference DEX); and the Node/Express backend services (access-control + testnet faucet) with their Postgres/RLS layer.

**Not covered (out of scope or requires separate tracks).**
- The **upstream Cosmos EVM / `evmd` codebase** itself — its pre-v1 audit is a documented hard launch blocker (CLAUDE.md §16 risk 6, ADR-006) and remains the founder's separate track.
- **Economic / game-theoretic modeling** of the §16.8 security-budget tail beyond confirming the code path exists.
- **Deployment & key-management posture** (HSM/`tmkms`/Vault, server hardening, reverse-proxy config) — runbooks exist but live infrastructure was not pen-tested.
- **Frontend** code and the **Blockscout/explorer** stack.
- Dynamic testing was not performed against a live network; findings are from source review plus the project's existing test suites.

This audit does not clear the project's own §16 hard launch gates (upstream audit; tail-reward + bonded-ratio monitoring), which remain prerequisites for a public mainnet launch independent of the findings above.
