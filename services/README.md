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
- **On-ramp / GembaPay (Phase 6) — mechanics DONE on-chain
  (`contracts/src/onramp/GembaOnRamp.sol`).** Fixed-rate stablecoin → GMB sale. **No
  fiat redemption, no DEX operated by us.** **MiCA gate (ADR-009): public sale is
  disabled by default and must NOT be enabled on a public network until a written
  MiCA sign-off from a Bulgarian fintech lawyer.** Built/tested on devnet only. Any
  future fiat-adjacent UX/marketing stays behind the same gate.
- **Indexers** — optional helpers feeding the frontend/explorer.

**Never commit:** DB passwords, API keys — use `.env` (placeholders in
`.env.example`).

## Phase

Built in **Phase 5** (access control) and **Phase 6** (on-ramp). Phase 0 placeholder.
