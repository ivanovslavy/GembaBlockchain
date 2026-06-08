# GembaBlockchain — Security Audit Report

**Date:** 2026-06-07
**Auditor:** Lead Security Auditor (multi-agent audit + adversarial verification)
**Scope:** GembaBlockchain monorepo — Solidity contracts, Go chain modules, backend services, dApps, deploy/harness scripts

---

## 1. Executive Summary

GembaBlockchain's security posture is **largely solid**. After a full multi-agent pass and an adversarial verification round, **no Critical, High, or (post-verification) Medium findings survived**. The confirmed issues are **seven Low** and **one Informational** — all either defense-in-depth hardening items, documentation accuracy corrections, deployment/operational guidance, or testnet-only (valueless-asset) exposures. None is a remotely-exploitable contract vulnerability that puts mainnet funds or consensus at risk.

Two findings were initially proposed at Medium severity (on-chain tenant isolation; PII plaintext-at-rest) and were **downgraded to Low during verification**: in both cases the underlying facts are accurate, but the claimed high-impact exploit assumes a deployment shape that contradicts the documented per-institution design, and the residual risk is real but bounded. One finding (cross-tenant access-log insert) was downgraded to **Info** — the only effect is an authenticated tenant polluting its *own* data, with no cross-tenant read, write, or practical disclosure.

The recurring theme across the Low findings is **documentation/comment claims that slightly overstate the protection actually enforced in code** (e.g. "cannot drain the reserve," "fail loud"), plus a handful of **operational hardening gaps** (per-institution contract deployment, at-rest encryption, durable rate-limit storage, key rotation). The core security architecture — Timelock-gated upgrades, supply invariants, non-voting reserves, RLS tenant isolation, soulbound access NFTs, and env-sourced secrets — is sound and consistently implemented.

The most actionable single item is operational, not architectural: **the live testnet drip-faucet account is the publicly-known cosmos/evm "dev2" mnemonic** (Finding L-7). It affects only valueless `gemba-testnet-1` tokens and is not a mainnet/§3 secrets violation, but it should be rotated.

---

## 2. Findings Summary

Severities reflect the **post-verification adjusted** ratings.

| ID | Severity | Component | Title |
|----|----------|-----------|-------|
| L-1 | Low | Reserves & UUPS upgradeability | Faucet granter EOA can rate-limited-drain to arbitrary destinations; "cannot drain" comment overstates protection |
| L-2 | Low | DEX (GembaSwap V2 / NativePool) | `GembaNativePool` allows zero-output "dust" swap that takes funds for nothing when `amountOutMin == 0` |
| L-3 | Low | Access NFT + Paymaster | No on-chain tenant isolation: single contract + single `ISSUER_ROLE` + flat global zone-id namespace |
| L-4 | Low | Backend (access-control) | Employee PII (`full_name`, `email`) stored plaintext at rest, no app-level encryption |
| L-5 | Low | Backend (testnet-faucet) | Rate-limit and global daily drip budget are in-process only — reset on restart, not shared across instances |
| L-6 | Low | Backend (access-control) | Zone (token id) namespace global on-chain but tenant-scoped off-chain — cross-tenant zone collision |
| L-7 | Low | Secret hygiene + dApps | Live testnet drip-faucet account controlled by a publicly-known committed mnemonic ("dev2") |
| I-1 | Info | Backend (access-control) | `access-logs` insert does not verify the referenced `employee_id` belongs to the calling tenant |

---

## 3. Detailed Findings

### L-1 — Faucet granter EOA: rate-limited (not absolute) drain; misleading in-code comment
- **Severity:** Low
- **Component:** Reserves & UUPS upgradeability (Faucet/Foundation/DAO/Contingency)
- **Location:** `contracts/src/reserves/Faucet.sol` — `grant()` (lines 76–91), comment lines 29–32; `contracts/script/DeployGovernance.s.sol:59` (granter = deployer/founder EOA)
- **Description:** At genesis the Faucet granter is the founder EOA. `grant()` lets the granter send up to `perGrantCap` per call to any `to`, bounded only by the rolling `epochCap` (deploy values: 1,000 GMB/call, 100,000 GMB/day on a 30,000,000 GMB reserve). `totalGranted` (line 88) is telemetry only — there is **no cumulative lifetime cap**. The comment at lines 29–32 claims "even a stolen granter key cannot drain the reserve," which is literally inaccurate: the epoch cap bounds **rate**, not eventual total.
- **Impact:** A compromised granter key could siphon ~100,000 GMB/day to attacker addresses and, undetected, drain the 30M faucet over ~300 days. Per-incident exposure = `epochCap × detection-and-response time`. The "no EOA key can drain reserves" invariant holds only in the slow-drain sense.
- **Mitigations already present (why this is Low):** `grant()` is access-controlled and `whenNotPaused`; `setGranter` (`onlyOwner`, line 104) revokes a compromised key instantly; `setEpochLimit`/`setPerGrantCap` throttle; EmergencyPause (2-of-3 guardians) can halt all grants without governance; large/uncapped transfers are gated to owner/Timelock via `release()`. This matches the consciously accepted trade-off in CLAUDE.md §16.5.
- **Recommendation:** Reword the comment to "rate-limited, not drain-proof." Prefer setting granter to a contract/multisig over the founder EOA; consider a destination allowlist and/or a cumulative lifetime cap; add a §16 decentralization-KPI monitoring alert when faucet outflow approaches `epochCap`.

### L-2 — `GembaNativePool` zero-output dust swap loses user funds when `amountOutMin == 0`
- **Severity:** Low
- **Component:** DEX (GembaSwap V2, WGMB, NativePool, LiquidityLocker)
- **Location:** `contracts/src/dex/GembaNativePool.sol` — `getAmountOut` (lines 64–69), `swapExactNativeForTokens` (~161–178), `swapExactTokensForNative` (~181–198)
- **Description:** `getAmountOut()` reverts only on zero `amountIn`/reserves; it returns a rounded-down **0** when `numerator < denominator` (tiny input vs reserves, or imbalanced/decimal-mismatched pools). Neither swap guards against `amountOut == 0`. With `amountOutMin = 0`: `swapExactNativeForTokens` does `reserveNative += msg.value` (pool keeps the native) and transfers 0 tokens; `swapExactTokensForNative` pulls the input and sends 0 native. The slippage check (`0 < 0`) is false, so no revert.
- **Impact:** User loses input for zero output on dust/rounding-sized swaps. Self-inflicted (requires tiny input **and** no slippage bound — only tests/demos do this); gains accrue to existing LPs; a third party cannot trigger it against others. This is strictly less safe than the Uniswap path it mirrors (`pair.swap` reverts `INSUFFICIENT_OUTPUT_AMOUNT` even with `amountOutMin = 0`), and contradicts the contract's own stated "fail loud" standard.
- **Recommendation:** Add `if (amountOut == 0) revert InsufficientOutputAmount();` immediately after `getAmountOut()` in both swap functions.

### L-3 — No on-chain tenant isolation in AccessControlNFT (single contract, single issuer, flat zone namespace)
- **Severity:** Low (proposed Medium → downgraded)
- **Component:** Access NFT + Paymaster
- **Location:** `contracts/src/access/AccessControlNFT.sol` (`ISSUER_ROLE`/`grantAccess`/`revokeAccess`); `services/access-control/src/server.js:11–15` (single `ACCESS_CONTROL_NFT_ADDRESS` + `ACCESS_ISSUER_PK`)
- **Description:** The off-chain backend enforces per-institution isolation via PostgreSQL FORCE RLS, but the paired on-chain layer provides none **if a single contract is shared across institutions**: `grantAccess`/`revokeAccess` are gated by one global `ISSUER_ROLE`, and `zone` is a flat `uint256` token-id namespace with no per-tenant scoping. The service wiring (one address + one issuer key) implies a shared-contract deployment.
- **Impact (as bounded by verification):** In a shared-contract model, tenant A's "zone 5" equals tenant B's token id 5 (cross-tenant collision), and one leaked issuer key could mass-grant/mass-revoke across all tenants. **However**, this is a *deployment-shape* risk, not a code bug: the contract is designed per-institution (`constructor(address admin)` grants a single `DEFAULT_ADMIN_ROLE` documented as "governance / the institution"; ADR-011 frames each institution running its own infra). Under the documented one-contract-per-institution model, distinct addresses make collisions impossible and scope any key compromise to one tenant. The contract's access control (onlyRole, soulbound `_update`, zero-address/already-granted checks) is correct; there is no attacker-triggerable code defect.
- **Recommendation:** Deploy one `AccessControlNFT` instance + issuer key per institution and **document/enforce that invariant** in deploy + service config. If a shared contract is ever required, namespace zone ids by tenant (`keccak(tenantId, zone)`) and scope authority per-tenant. Door controllers must verify the `(contract address, zone id)` pair, never zone id alone.

### L-4 — Employee PII stored plaintext at rest, no application-level encryption
- **Severity:** Low (proposed Medium → downgraded)
- **Component:** Backend services (access-control)
- **Location:** `services/access-control/db/schema.sql:35–43` (employees table); `src/db.js` `createEmployee()` (~78–84)
- **Description:** `full_name` and `email` (and the identity→wallet bridge) are plain `text`. `pgcrypto` is present but used only for `gen_random_uuid()` (line 17). Confidentiality rests on RLS + OS/filesystem controls. RLS governs SQL access via the `gemba_app` role but does not protect an offline copy (pg_dump, base-backup, WAL archive, replica, stolen disk).
- **Impact (as bounded by verification):** An offline artifact would expose rosters + employee→wallet linkage in cleartext — a GDPR concern. **But** this is defense-in-depth, not an app-exploitable defect: CLAUDE.md §10 and the schema header deliberately define RLS + off-chain deletability as the PII guard; no API path leaks cross-tenant PII while RLS holds; `assertSafeDbRole()` (db.js:19–30) aborts startup on a superuser/BYPASSRLS role, neutralizing the "compromised superuser connection" vector; the remaining vectors require prior infrastructure compromise normally mitigated one layer down (full-disk + encrypted backups), outside this file's responsibility.
- **Recommendation:** Require full-disk/volume encryption **and** encrypted, access-controlled backups; ideally add application-layer envelope encryption of `full_name`/`email` with a KMS/secret-store key (§3) so a raw dump yields ciphertext. Document the chosen control in the schema/README as an enforced requirement.

### L-5 — testnet-faucet rate-limit and daily drip budget are in-process only
- **Severity:** Low
- **Component:** Backend services (testnet-faucet)
- **Location:** `services/testnet-faucet/src/ratelimit.js` (in-memory `Map`); `src/server.js:25–39` (`dripDay`/`dripCountToday` module globals)
- **Description:** Per-address/IP cooldowns and the `DAILY_GLOBAL_MAX` counter live in process memory. A restart (deploy/crash/OOM/rotation) zeroes the budget and clears cooldowns; multiple instances behind the proxy multiply the effective budget by instance count. The code comments acknowledge the in-process limitation.
- **Impact:** An attacker who induces/awaits restarts (or benefits from routine redeploys) can exceed `DAILY_GLOBAL_MAX` and re-drip. **Bounded:** the hard control is `MIN_BALANCE_WEI` (server.js:24), checked on every drip against the live on-chain balance (lines 81–86) — it is stateless/restart-durable and floors the account regardless of in-memory resets, so the account cannot actually be drained. Tokens are valueless `gemba-testnet-1` GMB. Net effect is operational: faster drip to the floor + refill churn.
- **Recommendation:** Back the cooldown limiter and daily counter with a shared, restart-durable TTL store (e.g. Redis, keyed per day) before relying on these limits in any multi-instance or value-bearing deployment.

### L-6 — Zone (token id) namespace global on-chain but tenant-scoped off-chain
- **Severity:** Low
- **Component:** Backend services (access-control)
- **Location:** `services/access-control/src/chain.js` (single shared issuer wallet; `grantAccess(wallet, zone)` mints `zone` as ERC-1155 token id); `db/schema.sql` `capabilities.zone`; `app.js GET /access/:wallet/:zone`
- **Description:** All institutions share one issuer key + one contract, and off-chain `zone` is passed straight through as the on-chain token id with no per-tenant derivation. Two tenants both using zone 5 map to the same token id. `app.js` `GET /access/:wallet/:zone` calls `chain.hasAccess(wallet, zone)` directly without consulting the tenant-scoped `capabilities` table, so the on-chain check has no tenant boundary.
- **Impact:** *Conditional:* if a door/reader interprets a bare `(wallet, zone)` on-chain check without constraining the wallet set to its own tenant, a capability minted by tenant A for zone 5 satisfies tenant B's zone-5 check. Off-chain RLS remains correct (no PII leak). Practical exploitation additionally needs zone-id reuse across tenants on a shared contract, an attacker holding that zone, and physical reach to the second tenant's door; employees have distinct wallets (`UNIQUE(tenant_id, wallet)`). CLAUDE.md §10 intentionally keeps the on-chain layer anonymous (address-holds-zone), with tenant identity off-chain only.
- **Recommendation:** Derive the on-chain token id from a tenant-namespaced value (`keccak(tenant_id, zone)` or a high-bits tenant prefix), **or** deploy one contract/issuer per institution, **or** document and enforce that every reader scopes `hasAccess` checks to its own tenant's wallet list.

### L-7 — Live testnet drip-faucet account controlled by a publicly-known committed mnemonic
- **Severity:** Low
- **Component:** Secret hygiene + dApps + harness
- **Location:** `chain/gembad/init-gembad-multinode.sh:24` and `chain/scripts/init-multinode.sh:22` (cosmos/evm "dev2" mnemonic); funded address at `chain/testnet/testnet.params.sh:20` (`TN_FAUCET_ADDR_0X`, commented `# dev2`); published at `frontend/addresses/index.html:83`
- **Description:** The committed dev2 mnemonic derives (eth_secp256k1, `m/44'/60'/0'/0/0`) to `0x40a0cb1C63e026A81B55EE1308586E21eec1eFa9` — byte-for-byte the live `tnfaucet (drip faucet service)` account (2,000,000 GMB on `gemba-testnet-1`). The on-chain account is therefore signable by **anyone** with repo access, regardless of the faucet service correctly loading its key from env. `testnet.params.sh:17–19` already documents the intended fix (fresh env-only key, no committed fallback), but the funded address was never rotated, so the exposure is live. Previously logged as round-3 Finding 9; remains open.
- **Impact:** Any repo reader can sign from the live drip account and sweep/grief its 2M test GMB, taking public onboarding offline (availability/DoS). **Bounded and recoverable:** `gemba-testnet-1` tokens (EVM chainId 821207) are valueless by design and distinct from mainnet; no monetary loss; **not** a mainnet or CLAUDE.md §3/§14 secrets violation. The other two committed dev mnemonics are ephemeral local-devnet recipients holding no live funds.
- **Recommendation:** Re-fund the live drip account from a freshly generated keypair whose mnemonic lives only in the operator secret store, and update `TN_FAUCET_ADDR_0X`. Keep the public dev2 key strictly for ephemeral local bootstrap. Treat the current 2M drip balance as compromised until rotated.

### I-1 — `access-logs` insert does not verify `employee_id` belongs to the calling tenant
- **Severity:** Informational
- **Component:** Backend services (access-control)
- **Location:** `services/access-control/src/app.js` `POST /access-logs` (lines 57–63) → `src/db.js` `repo.logAccess()`
- **Description:** Unlike `POST /capabilities` (which gates on the RLS-scoped `getEmployeeWallet()`), the access-logs handler inserts directly with the client-supplied `employee_id`. The `access_logs` RLS `WITH CHECK` validates only `tenant_id` (bound server-side to the caller, db.js:119); the FK to `employees(id)` is a system constraint that bypasses RLS. So a tenant can insert a log row referencing another tenant's employee UUID.
- **Impact:** Effectively nil. RLS forces `tenant_id` to the attacker's own, so the row lands only in the attacker's own log set (no cross-tenant write); there is **no read endpoint** for `access_logs`, so rows never surface (no disclosure); the FK-existence oracle relies on 122-bit `gen_random_uuid()` values and is not enumerable. Net: an attacker corrupting referential integrity within its own data — which it can already do freely.
- **Recommendation:** For consistency/defense-in-depth, gate `logAccess` like `createCapability`: resolve the employee via the RLS-scoped existence check first and reject (400/404) if it is not tenant-owned.

---

## 4. What's Solid

These strengths were observed directly in code and are genuinely well-implemented:

- **Reserve access control & throttling.** `Faucet.grant()` is access-controlled, `whenNotPaused`, per-call capped, and rolling-window capped; `setGranter` allows instant revocation of a compromised key; large transfers are gated to owner/Timelock. Reserve contracts are non-voting per design.
- **UUPS upgrades gated by Timelock.** Upgrade authority is Governor + Timelock, never an EOA (per Phase-3 principles), with supermajority Governor and a pause-only EmergencyPause that can halt but not move funds.
- **Soulbound access NFTs done right.** `AccessControlNFT` enforces `onlyRole` on grant/revoke, blocks transfers via `_update`, and validates zero-address / already-granted / not-granted conditions. No PII on-chain (§10 respected).
- **Off-chain tenant isolation.** PostgreSQL FORCE RLS isolates each institution's identity rows; `assertSafeDbRole()` refuses to start on a superuser/BYPASSRLS role; PII is deletable off-chain to satisfy GDPR erasure.
- **Faucet hard floor.** The testnet faucet's `MIN_BALANCE_WEI` check is stateless and evaluated against live on-chain balance on every drip — a durable anti-drain control that survives restarts and multi-instance deployment.
- **Secret hygiene for mainnet.** Mainnet-class secrets are env-sourced with no committed fallbacks (e.g. `TN_FAUCET_MNEMONIC`); the only committed mnemonics are the well-known cosmos/evm dev keys, explicitly flagged as never-for-mainnet. The one live exposure (L-7) is testnet-only and valueless.
- **DEX faithfulness.** The Uniswap V2 fork preserves upstream invariants on the router path (`INSUFFICIENT_OUTPUT_AMOUNT` revert on zero output); the lone gap (L-2) is confined to the bespoke native-pool wrapper and is a one-line fix.

No supply-inflation, minting, reentrancy, or consensus-level defects survived verification.

---

## 5. Scope & Method

- **Approach:** Multi-agent security audit across the monorepo — Solidity contracts (`contracts/`), Go chain modules (`chain/`), backend services (`services/`), dApps/frontend, and deploy/harness scripts — followed by an **adversarial verification round** in which each candidate finding was re-checked against the actual code, challenged with refutations, and re-scored (several were downgraded; this report reflects post-verification severities).
- **Covered:** reserve/treasury contracts and UUPS upgradeability, DEX contracts, access-control NFT + paymaster path, access-control backend (RLS, PII handling, API authorization), testnet faucet service, and committed-secret/key-hygiene review including on-chain address derivation to confirm live exposure.
- **Not covered / limitations:** No live mainnet existed to test against; on-chain claims for testnet were verified against committed config and the documented re-genesis state, not exhaustive live-chain probing. This review does **not** substitute for the outstanding **upstream Cosmos EVM audit (ADR-006)** or a formal mainnet pre-launch audit, both of which remain hard launch blockers per CLAUDE.md §16. Economic/game-theoretic modeling of the long-term security budget (ADR-008) and infrastructure/DevOps configuration (reverse proxy, KMS/tmkms, backups) were reviewed only where they intersected the findings above.

**Bottom line:** No Critical/High/Medium issues. Address L-7 (rotate the testnet drip key) and the L-1/L-2 in-code corrections promptly; treat L-3/L-4/L-6 as deployment-and-hardening requirements to lock in before any multi-institution production rollout.

---

## Remediation & acceptance (2026-06-08)

**FIXED in code:**
- **L-1** Faucet: comment corrected — the epoch cap bounds RATE, not lifetime total; it is NOT
  drain-proof (the real responses are setGranter revoke + EmergencyPause). Accepted trade-off §16.5.
- **L-2** GembaNativePool: both swaps now `revert InsufficientOutputAmount()` when `amountOut == 0`
  (no more zero-output dust swap that takes funds for nothing). 100/100 forge tests.
- **I-1** access-control `/access-logs`: verifies the `employee_id` belongs to the calling tenant
  (RLS-scoped lookup) before inserting, matching `/capabilities`.

**ACCEPTED (architectural / operational / documented trade-offs — not code defects):**
- **L-3 + L-6** On-chain tenant isolation: the intended deployment is **one AccessControlNFT +
  issuer per institution** (CLAUDE.md §9/§10 — the chain layer is anonymous "address-holds-zone",
  tenant identity lives off-chain). The shared-contract wiring in the example service is a default;
  production deploys per-institution (or namespaces the token id by `keccak(tenant_id, zone)`).
  Off-chain RLS isolation is correct regardless.
- **L-4** PII at-rest encryption: §10's PII guard is RLS + off-chain deletability; full-disk +
  encrypted-backup is a mandated infra control. App-layer envelope encryption of name/email is a
  tracked hardening enhancement (KMS), not a blocker.
- **L-5** Faucet rate-limit durability: in-process by design for the single-instance testnet drip;
  back with Redis before any multi-instance/value-bearing use. The min-balance breaker (stateless,
  on-chain) already hard-floors the account.
- **L-7** Live testnet drip account uses the public dev2 key: **operational rotation task** — re-fund
  a fresh operator-only keypair on `gemba-testnet-1` and update `TN_FAUCET_ADDR_0X`. Valueless
  testnet tokens; not a mainnet/§3 violation.

## Verdict across 5 rounds
Findings by round: 12 → 9 → 10 → 6 → **8**. **Zero Critical / High / Medium for the last several
rounds.** No exploitable fund-loss, supply-inflation, reserve-drain, or consensus-halt path exists.
Remaining items are low-severity defense-in-depth, deployment-shape guidance, prod-ops hardening,
and one valueless-testnet key rotation. The core architecture (Timelock-gated upgrades, fixed-supply
invariant, non-voting reserves, RLS isolation, soulbound access NFTs) is sound and consistently
implemented. Literal "zero findings" is not a realistic target for an adversarial deep audit; the
achieved and stable result is **no Critical/High/Medium**, with lows triaged to fix-or-accept.
