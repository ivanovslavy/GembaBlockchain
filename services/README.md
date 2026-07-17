# /services — Node.js / Express backends

Off-chain services. The critical GDPR rule (`CLAUDE.md` §10): **PII and physical
access logs never go on-chain.**

## What goes here

- **Access-control API (Phase 5) — DONE: [`access-control/`](./access-control).**
  Maps employee identity ↔ anonymous capability NFT. Identity, the identity→NFT
  mapping, and all access logs live in **PostgreSQL with `FORCE` row-level security**
  (per-institution isolation), never on-chain. The on-chain side stays verifiable;
  the private data stays deletable (GDPR right to erasure). 8 unit tests + an RLS
  integration test.
- **Buy-GMB / GembaPay (Phase 6) — [`purchase-backend/`](./purchase-backend) +
  `contracts/src/onramp/GembaPayDispenser.sol`.** GMB is sold ONLY via the
  gembachain.io "Buy GMB" UI → GembaPay backend → owner-only dispenser (fixed
  1 GMB = 1 EUR). **No fiat redemption, no DEX operated by us.** The on-chain
  `GembaOnRamp` public-sale contract was **REMOVED entirely (owner decision
  2026-07-17)** — the MiCA-gated public sale no longer exists in the codebase;
  any future fiat-adjacent UX/marketing stays behind the same MiCA gate (ADR-009).
- **Indexers** — optional helpers feeding the frontend/explorer.

**Never commit:** DB passwords, API keys — use `.env` (placeholders in
`.env.example`).

## Phase

Built in **Phase 5** (access control) and **Phase 6** (on-ramp). Phase 0 placeholder.
