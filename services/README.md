# /services — Node.js / Express backends

Off-chain services. The critical GDPR rule (`CLAUDE.md` §10): **PII and physical
access logs never go on-chain.**

## What goes here

- **Access-control API (Phase 5)** — maps employee identity ↔ anonymous capability
  NFT. Identity, the identity→NFT mapping, and all access logs live in **PostgreSQL
  with row-level security**, never on-chain. The on-chain side stays verifiable; the
  private data stays deletable (GDPR right to erasure).
- **On-ramp / GembaPay (Phase 6)** — stablecoin → GMB purchase flow. **No fiat
  redemption, no DEX operated by us.** Blocked for public use until MiCA sign-off
  (ADR-009).
- **Indexers** — optional helpers feeding the frontend/explorer.

**Never commit:** DB passwords, API keys — use `.env` (placeholders in
`.env.example`).

## Phase

Built in **Phase 5** (access control) and **Phase 6** (on-ramp). Phase 0 placeholder.
