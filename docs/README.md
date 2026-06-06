# /docs — Specs & runbooks

Detailed specifications and operational runbooks for GembaBlockchain. The
**top-level design source of truth is [`../CLAUDE.md`](../CLAUDE.md)**; documents
here expand on specific areas.

## Index

- [`risks.md`](./risks.md) — **Risk & Decision Register** (ADR format). Every
  conscious trade-off in long form, including the long-term security budget
  (ADR-008), gas-price-in-real-value (ADR-008a), the two electorates (ADR-008b),
  the withdrawn MiCA / public-sale gate (ADR-009 — no liquidity/no public sale by
  design), and de-facto-centralized-at-genesis (ADR-010). Mirrors `CLAUDE.md` §16.

- [`testnet-status.md`](./testnet-status.md) — **live status of the test network**:
  what is verified working end to end, and the record of the **first GMB transaction**
  indexed in GembaScan. The valueless dress-rehearsal testnet, not mainnet.

- [`phase3-treasury-principles.md`](./phase3-treasury-principles.md) — binding
  principles for the Phase 3 Solidity contracts: **tests first, funding last**
  (no contract funded before unit + invariant/fuzz + Slither; reserves also need
  an audit before mainnet genesis), upgrade authority is Governor+Timelock only
  (never an EOA), and the Cosmos↔EVM seam where `x/feesplit` deposits into the
  Solidity Faucet.

- [`runbooks/`](./runbooks) — **Phase 9 node-operations runbooks**: peers & pruning
  (validator vs archive), validator key management (tmkms), backups, halt recovery,
  and coordinated upgrades. Pair with [`/monitoring`](../monitoring) (Prometheus +
  the bonded-ratio security metric, ADR-008).

## Planned (later phases)

- Public-launch checklist gating on the hard blockers (audit ADR-006, security-budget
  tail ADR-008 — the tail reward is implemented; the audit is the founder's separate,
  non-code track). The MiCA / public-sale gate (ADR-009) was withdrawn — no liquidity,
  no exchange, no public sale by design.
