# /docs — Specs & runbooks

Detailed specifications and operational runbooks for GembaBlockchain. The
**top-level design source of truth is [`../CLAUDE.md`](../CLAUDE.md)**; documents
here expand on specific areas.

## Index

- [`risks.md`](./risks.md) — **Risk & Decision Register** (ADR format). Every
  conscious trade-off in long form, including the long-term security budget
  (ADR-008), gas-price-in-real-value (ADR-008a), the two electorates (ADR-008b),
  MiCA as a launch blocker (ADR-009), and de-facto-centralized-at-genesis (ADR-010).
  Mirrors `CLAUDE.md` §16.

- [`phase3-treasury-principles.md`](./phase3-treasury-principles.md) — binding
  principles for the Phase 3 Solidity contracts: **tests first, funding last**
  (no contract funded before unit + invariant/fuzz + Slither; reserves also need
  an audit before mainnet genesis), upgrade authority is Governor+Timelock only
  (never an EOA), and the Cosmos↔EVM seam where `x/feesplit` deposits into the
  Solidity Faucet.

## Planned (later phases)

- Halt-recovery runbook (Phase 9).
- Coordinated node-operator upgrade runbook (chain binary/consensus changes are
  social coordination, not on-chain governance — `CLAUDE.md` §7).
- Validator key-management guide (KMS/Vault/`tmkms`, Phase 9).
- Archive vs pruned node disk-sizing guidance (`CLAUDE.md` §11).
