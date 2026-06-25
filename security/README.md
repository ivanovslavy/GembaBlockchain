# GembaBlockchain — Adversarial Security Testing Harness

Reusable, re-runnable **offensive** test campaign: actively try to steal, mint, drain,
halt, bypass, and DoS GembaBlockchain, and prove the CLAUDE.md §3 invariants hold. This
complements the static audits (`docs/security-audit-2026-06-08*.md`) and the unit/fuzz
test suites — it is the *attacker's playbook*, not happy-path tests.

**Report:** `docs/security-pentest-2026-06-24.md` (findings, severity, repro, fix).

## ⚠️ SAFETY RULES (read before running anything)

Tests are tagged by reversibility:

| Class | Where it runs | Examples |
|-------|---------------|----------|
| **Non-destructive** | live testnet OK | RPC read probes, method-exposure, secret scan, fuzzing with bad input only |
| **Destructive-recoverable** | live testnet (with `docs/runbooks/halt-recovery.md` open) | downtime slash of one validator (unjail after), gov-param attack we then revert |
| **Destructive-irreversible** | **local devnet ONLY** | double-sign / tombstone, supply-corruption attempts |

- Never move funds you don't own. P-1 (a live key recoverable from the repo) was
  *demonstrated by reading balances only* — do not sweep.
- Live destructive tests are authorized by the operator; still stage them and keep the
  recovery runbook ready. `double-sign` is devnet-only (tombstone is permanent).

## Layout

```
security/
  README.md                  # this file
  devnet/                    # local 4-validator devnet for Track 2 (build gembad, genesis, run)
  lib/                       # shared JS: rpc client, wallet gen, JSONL logger (reuse stress/lib)
  track2-consensus/          # double-sign, slash→faucet, min-self-bond, gov, halt, supply-invariant
  track3-rpc-infra/          # rpc method-exposure (done), JSON-RPC fuzz, DoS, rate-limit, secret scan
  track4-services-dapp/      # faucet drain/sybil, access-control isolation+DoS, injection, frontend
  results/                   # JSONL logs (gitignored)
contracts/test/adversarial/  # Track 1 Foundry suite (kept in the contracts project so it
                             # compiles against src/ and runs with `forge test`)
```

## Running

```bash
# Track 1 — treasury/governance adversarial suite (safe, local)
cd contracts && forge test --match-path 'test/adversarial/*.t.sol' -vv

# Track 3 — live RPC method-exposure probe (non-destructive, read-only)
bash security/track3-rpc-infra/rpc-expose-probe.sh     # see report P-2/P-3

# Track 3 — secret scan (working tree + history)
bash security/track3-rpc-infra/secret-scan.sh          # see report P-1

# Track 2 — local devnet for destructive consensus tests (TODO: build harness)
# bash security/devnet/up.sh && bash security/track2-consensus/run.sh
```

## Status — COMPLETE (see docs/security-pentest-2026-06-24.md)

- ✅ Track 1 — treasury/governance, 6/6 attacks defended (`Track1_TreasuryAttack.t.sol`)
- ✅ Track 2 — consensus: supply invariant held live (100M constant under streaming),
  feemarket 1-gwei floor + 100M gas limit confirmed live; **min-self-bond bypass on the
  deployed binary → P-4 (build/deploy drift, verify live)**
- ✅ Track 3 — method-exposure + secret scan + JSON-RPC fuzz + rate-limit probe
  (P-1 High, P-2 Low-Med, P-3 Low; fuzzing graceful everywhere)
- ✅ Track 4 — faucet sybil/restart bypass demonstrated (bounded); service suites pass;
  frontend token-import (T-1 Medium) + error-leak (T-2) + RPC failover (T-3)

Remediation: P-1/P-2/P-3 fixed in code + funds rotated; operator steps in
`docs/runbooks/pentest-2026-06-24-remediation.md`. **P-4 needs live-validator verification.**
