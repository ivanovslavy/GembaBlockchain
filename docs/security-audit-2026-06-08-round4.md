# GembaBlockchain — Security Audit Report

**Date:** 2026-06-07
**Auditor:** Lead Security Auditor (multi-agent audit + adversarial verification)
**Scope:** GembaBlockchain monorepo — Solidity contracts, Go chain modules, backend services, dApps, secret hygiene

---

## 1. Executive Summary

The GembaBlockchain codebase is, overall, **in solid security shape**. The high-value attack surface — the on-chain treasury/governance contracts and the chain's supply invariant — held up well under adversarial review: no critical smart-contract vulnerabilities, no reentrancy holes, no minting-after-genesis path, and no centralization backdoor were confirmed. The reserve-exclusion, UUPS-via-Timelock, and RLS-isolation designs all function as documented for their intended (genesis/primary) use cases.

After adversarial verification, **6 findings were confirmed**, but most were materially down-graded from their initial severity because primary controls already bound the blast radius. The net result:

- **1 HIGH** — an operational secret-hygiene issue (a live, acknowledged-exposed GitHub PAT that has not been rotated). This is the one item warranting immediate action.
- **5 LOW** — incomplete secondary controls and off-chain robustness gaps, all bounded by primary controls, trusted roles, or the fact that they affect only valueless testnet assets.

There were **zero Critical** findings. The single HIGH is a credential-rotation task, not a code defect. The on-chain core that actually secures funds is sound; the confirmed issues are defense-in-depth gaps and ops hygiene rather than exploitable fund-loss bugs.

**Top priority:** revoke and rotate the GitHub PAT (Finding H-1) now.

---

## 2. Findings Summary

| ID | Severity | Component | Title |
|----|----------|-----------|-------|
| H-1 | **High** | Secret hygiene | Live GitHub PAT (self-flagged as leaked) still active and unrotated in working-tree `.env` |
| L-1 | Low | Governance | Reserve exclusion bypassable via delegation for the dynamic `setExcluded` path |
| L-2 | Low | Tickets/Perks | `GembaPerks.payBonusBatch` exposed to gas-griefing by a malicious contract recipient |
| L-3 | Low | Backend (testnet-faucet) | Per-address/per-IP cooldown bypassable: `tryAcquire()` return discarded + TOCTOU across an `await` |
| L-4 | Low | Backend (access-control) | Chain client lacks nonce serialization (faucet's finding-#8 fix not ported) |
| L-5 | Low | Secret hygiene | `wallet-backup/` holds real testnet keys in a world-readable directory |

*(Severities reflect post-verification adjusted ratings; H-1 was raised and L-1/L-3/L-4 were lowered during verification.)*

---

## 3. Detailed Findings

### H-1 — Live GitHub PAT, acknowledged-exposed and unrotated

- **Severity:** High
- **Component:** Secret hygiene
- **Location:** `/home/slavy/GembaBlockchain/.env` (line 11, `GITHUB_TOKEN=github_pat_11BQ3…`)
- **Description:** The untracked `.env` contains a full fine-grained GitHub Personal Access Token. The author's own inline comment directly above it reads: *"ROTATE: this value passed through a chat transcript. Revoke + regenerate."* The token value is still present in full, strongly indicating it was never rotated (a rotation would have replaced the value). The token is used for repo / chain-registry push automation. The `.env` is correctly gitignored, untracked, and was never committed (verified: `git ls-files` and `git log --all -- .env` both empty) — so this is **not** a repository leak. The exposure vector is the chat transcript the author themselves flagged.
- **Impact:** A write-capable GitHub credential, known to have been exposed and used for push access to repos slated to go public, can be used by anyone with transcript or local-file access until it is revoked. Mitigating factors that keep this below critical: the PAT is fine-grained/scoped (per the comment it is 403'd from external-repo PRs), it is stored locally and gitignored, and the leak channel is a limited-access transcript, not the public repo.
- **Recommendation:** Revoke the token immediately (GitHub → Settings → Developer settings → Personal access tokens), generate a replacement, update `.env`, and confirm the old token is dead. Never paste live tokens into prompts/transcripts going forward.

---

### L-1 — Reserve exclusion bypassable via delegation (dynamic `setExcluded` path)

- **Severity:** Low (initially Medium)
- **Component:** Governance (Governor/Timelock/Votes/EmergencyPause)
- **Location:** `contracts/src/governance/GembaVotes.sol:92-99` (`getVotes`/`getPastVotes`) and `:86-89` (`_update`)
- **Description:** Reserve exclusion is enforced three ways: `_update` blocks transfers **to** an excluded address, `depositFor` blocks minting to one, and `getVotes`/`getPastVotes` return 0 for an excluded **delegatee**. OZ `ERC20Votes` accounts voting power by delegatee and this contract overrides neither `_getVotingUnits` nor `delegate`/`_delegate`. Consequently, an address that **already holds** vGMB and is **later** excluded via `setExcluded` can `delegate()` its balance to a non-excluded proxy; the proxy's `getPastVotes` is computed via `super` (not zeroed) and still includes the excluded holder's units. The override only zeroes the excluded account's *own* delegated weight, not weight it delegates *out*.
- **Impact:** Defeats the §3/§7 "reserves never vote" invariant only for the dynamic exclude-after-holding path. The primary controls (block transfers/mints **to** excluded) mean the four genesis reserves never receive vGMB and thus have no units to delegate, so the documented invariant is preserved in practice. The `getVotes` zeroing is explicitly labelled defense-in-depth. The bypass requires the contrived case of a generic holder excluded after acquiring units, evading via a self-controlled proxy — and `setExcluded` is itself Governor/Timelock-gated.
- **Recommendation:** Make exclusion strip delegated-out weight: on `setExcluded(true)`, force the account's delegate to `address(0)` and block excluded accounts from delegating (override `_delegate`/`delegate`), or have `getVotes` subtract weight delegated **from** excluded accounts. Add a test exercising exclude-after-holding + delegate.

---

### L-2 — `GembaPerks.payBonusBatch` gas-griefing by a malicious contract recipient

- **Severity:** Low
- **Component:** On-ramp + Tickets/Perks
- **Location:** `contracts/src/tickets/GembaPerks.sol` — `payBonusBatch` (L55), `_tryPayBonus` (L83-95)
- **Description:** `_tryPayBonus` uses `payable(employee).call{value: amount}("")` with no gas cap, forwarding all remaining gas. A contract recipient can consume ~63/64 of the gas at that iteration before returning; the OOG/`ok=false` is caught (emits `BonusFailed`) but the gas is already burned. A malicious recipient early in the batch can starve later legitimate recipients in the same call. The `nonReentrant` guard correctly prevents reentrancy — this is purely a gas-consumption griefing vector.
- **Impact:** Bounded and low. `payBonusBatch` is `onlyRole(DISTRIBUTOR_ROLE)` (trusted HR/ops controls the arrays); recipients are the institution's own employees; the griefing recipient forfeits its own bonus; balance is re-read each iteration so no funds are lost; recovery via re-run or single `payBonus` is trivial. The per-recipient isolate-failures pattern was already a deliberate choice for a prior audit finding.
- **Recommendation:** Forward a bounded gas stipend (`call{value: amount, gas: <cap>}`) or, preferably, switch to a pull-payment model (credit a withdrawable balance, let employees claim) to remove the per-recipient external call from the loop. Weigh the cap against breaking legitimate contract recipients.

---

### L-3 — PublicReserve cooldown bypassable: `tryAcquire()` return discarded + TOCTOU across an `await`

- **Severity:** Low (initially Medium)
- **Component:** Backend services (testnet-faucet)
- **Location:** `services/testnet-faucet/src/server.js`, `POST /drip` (lines ~65-79)
- **Description:** The handler gates on `byAddress.remaining()`/`byIp.remaining()` (synchronous, L65-68), then `await faucet.balance()` (L73) yields the event loop, and only afterward calls `byAddress.tryAcquire()`/`byIp.tryAcquire()` (L78-79) — **discarding** their boolean returns. Concurrent same-address requests all pass the `remaining()==0` check before any records a timestamp, then all drip regardless of `tryAcquire`'s result. The 24h per-address/per-IP cooldown does not hold under concurrency.
- **Impact:** Bounded and low. `globalBudgetAllow()` is concurrency-safe (no `await`), so `DAILY_GLOBAL_MAX` still hard-caps total daily drips; the min-balance breaker prevents drain. The per-address limiter is already documented (prior finding #7) as defeatable via fresh recipient addresses, so it was never the primary anti-drain control, and an attacker owns all addresses anyway. Tokens are valueless testnet GMB behind a reverse proxy.
- **Recommendation:** Acquire atomically **before** any `await` and honor the return: `if (!byAddress.tryAcquire(to, now)) return 429; if (!byIp.tryAcquire(ip, now)) { byAddress.release(to); return 429; }`, rolling back on later failure paths. Do not use `remaining()` as a gate separate from `tryAcquire()`.

---

### L-4 — access-control chain client lacks nonce serialization

- **Severity:** Low (initially Medium)
- **Component:** Backend services (access-control)
- **Location:** `services/access-control/src/chain.js`, `grantAccess`/`revokeAccess` (lines 14-34)
- **Description:** `faucet.js` serializes sends (its finding #8 fix) to avoid concurrent txs reading the same pending nonce; `chain.js` does not — `grantAccess`/`revokeAccess` call the contract directly with no queue. ethers v6 populates the nonce from `getTransactionCount(from,'pending')`, so concurrent sends from the single ISSUER wallet (concurrent `POST /capabilities`, or a grant racing the outbox retry worker) can collide and one tx is rejected.
- **Impact:** Lower than initially assessed. Grant collisions fail **loud**: `grantAccess` is awaited before `createCapability`, so a throw yields a 500 with no DB row written — DB and chain stay consistent (no silent capability loss). Revoke collisions **self-heal**: failed revokes are recorded to the outbox and retried by the 60s worker. Realistic worst case is spurious 500s on concurrent grants (caller retries) plus an extra outbox cycle — an availability/robustness gap, not silent divergence or a security vuln. The same nonce-collision class is unmitigated for the higher-value issuer key.
- **Recommendation:** Port the `serialize()` queue from `faucet.js` around `grantAccess`/`revokeAccess`, or manage an explicit per-signer incrementing nonce. Serializing suffices at low QPS; use a shared nonce manager for multi-instance.

---

### L-5 — `wallet-backup/` holds real testnet keys in a world-readable directory

- **Severity:** Low
- **Component:** Secret hygiene
- **Location:** `/home/slavy/GembaBlockchain/wallet-backup/` (dir mode 0775; `PRIVATE-KEYS.md`, `gemba-testnet-1-export.{json,txt}`)
- **Description:** The directory (mode 0775, world-readable/traversable) contains real eth_secp256k1 private keys for the testnet genesis EOAs and validator accounts; `PRIVATE-KEYS.md` holds 10 raw private keys and the export `.json`/`.txt` are mode 0664 (world-readable). It is correctly gitignored, untracked, and never committed (verified) — no repo leak. Note: contrary to the initial report, **no mnemonics** were found (raw keys only), and `keyring-raw/` is **properly protected** (subdirs 0700, `*.info` files 0600) — only the top-level human-readable copies leak.
- **Impact:** Low today: a second local account on the host could read live **testnet** (valueless) keys. The file header itself states these are testnet keys to be rotated before mainnet. The "critical if reused for mainnet genesis" scenario is conditional and explicitly guarded by the documented rotation requirement.
- **Recommendation:** `chmod 700 wallet-backup` and `chmod 600` the export/key files. Document explicitly that these keys MUST NOT be reused for mainnet genesis — generate fresh keys for mainnet.

---

## 4. What's Solid

The following strengths were observed and verified during the audit:

- **No critical smart-contract vulnerabilities.** No confirmed reentrancy, no fund-drain path, no minting-after-genesis. The supply invariant holds.
- **UUPS upgrades are Timelock-gated.** Upgrade authority routes through Governor + Timelock, not an EOA — consistent with the §3/§7 "no unilateral control of reserves" invariant.
- **Reserve exclusion works for its primary (genesis) case.** `_update` blocks transfers to excluded addresses and `depositFor` blocks minting to them, so the four genesis reserves can never acquire vGMB and never vote. (L-1 is a defense-in-depth gap only in the dynamic path.)
- **Reentrancy guards correctly placed.** `nonReentrant` on `GembaPerks` value paths defeats reentrancy (L-2 is gas-griefing only, not a reentrancy hole).
- **Per-recipient failure isolation in batch payouts** — a deliberate, audit-driven design that re-reads balance each iteration and never leaks funds on failure.
- **Off-chain identity isolation via PostgreSQL RLS** keeps each institution's PII rows separated; the GDPR on-chain-revoke + off-chain-delete split is implemented.
- **Loud-fail / self-heal backend semantics.** access-control grants fail loud (no DB/chain divergence) and revokes self-heal via the outbox worker — so even the unmitigated nonce gap (L-4) does not cause silent corruption.
- **Concurrency-safe global limits + balance breaker** on the faucet bound abuse even though the per-address cooldown (L-3) is defeatable.
- **Secret-hygiene design is correct in the repo.** `.env`, `wallet-backup/`, keyrings, and node data are all gitignored and verifiably never committed; `keyring-raw/` material is mode 0600/0700. The two secret findings (H-1, L-5) are operational (rotation, file permissions), not repository leaks.

---

## 5. Scope & Method

- **Method:** Multi-agent review across the monorepo (Solidity contracts, Go chain modules, Node/Express services, dApps, secret hygiene), followed by an **adversarial verification pass** in which each candidate finding was challenged — attempting to refute it via code reading, `grep` of overrides/guards, git history, and file-permission/credential checks. Only findings that survived refutation are reported; several initial severities were adjusted up (H-1) or down (L-1, L-3, L-4) during this pass, and one claim was partially corrected (L-5: no mnemonics; `keyring-raw/` is protected).
- **Covered:** governance/treasury contracts, tickets/perks contracts, on-ramp, testnet-faucet and access-control services, secret/credential hygiene and filesystem permissions, git history for leak verification.
- **Not covered / limitations:** No live mainnet deployment, no formal verification, no full economic/game-theory modeling of tokenomics, no penetration testing of deployed infrastructure (reverse proxy, hosts), and no audit of upstream Cosmos EVM (its pre-v1 upstream audit remains a separate, documented launch blocker — ADR-006). Findings are based on static review of the working tree as of 2026-06-07.

**Recommended action order:** H-1 (rotate the PAT) immediately; L-5 (`chmod`) and L-3 (one-line `tryAcquire` fix) are quick wins; L-1, L-2, L-4 are defense-in-depth/robustness improvements to schedule before mainnet.

---

## Risk acceptance & remediation (2026-06-08)

**H-1 (GitHub PAT) — ACCEPTED, not a leak, no action taken.** The "transcript" is a local
**Linux console / CLI session on the operator's own machine**, NOT a browser chat or any
external/third-party service. The token never left the operator's host: `.env` is gitignored,
untracked, and never committed (verified — no repo leak), and there is no external transmission
channel. There is therefore **no exposure to rotate against**. The token stays as-is.

**Code findings — FIXED:**
- **L-1** GembaVotes: excluded accounts can no longer delegate out — `_delegate` reverts for an
  excluded delegator, and `setExcluded(true)` strips any existing delegation (force-delegate to 0).
- **L-2** GembaPerks.payBonusBatch: per-recipient `call` now forwards a bounded gas stipend, so a
  malicious contract recipient can't burn the batch's gas (single `payBonus` stays uncapped).
- **L-3** testnet-faucet `/drip`: cooldowns acquired atomically (honoring `tryAcquire`'s return)
  BEFORE any `await`, closing the TOCTOU race.
- **L-4** access-control `chain.js`: `grantAccess`/`revokeAccess` now serialize sends (ported the
  faucet's nonce-serialization fix), preventing nonce collisions from the single ISSUER wallet.
- **L-5** `wallet-backup/` permissions tightened (`chmod 700` dir, `600` files); testnet keys only,
  to be regenerated for mainnet.
