# GembaBlockchain

A **decentralized, permissionless, public Proof-of-Stake L1** with full EVM
compatibility. Anyone with enough stake can validate; anyone can hold and send the
native coin **Gemba (GMB)**. No central operator decides who participates.

GMB is a **utility coin** — value comes from *use* (cheaper service access,
workplace access control, event tickets, employee perks), not speculation. The
long-term goal is infrastructure **owned and run by the institutions and community
that use it**, where every participant follows the same on-chain rules and no one —
including the founder or a municipality — has special power.

> **The single source of truth is [`CLAUDE.md`](./CLAUDE.md).** If a design
> decision changes, update `CLAUDE.md` first, then the docs, then the code.

## Core facts

| | |
|---|---|
| Network | GembaBlockchain |
| Native coin | Gemba (**GMB**) — staking + gas coin |
| Framework | Cosmos SDK + Cosmos EVM (`cosmos/evm`, `evmd`) on CometBFT |
| Consensus | CometBFT BFT PoS — instant finality (~2 s), no reorgs |
| Cosmos chain-id | `gemba-1` · EVM chainId **821206** |
| Accounts | `eth_secp256k1`, coin type 60 → standard `0x...`, MetaMask works |
| Supply | **fixed**, minted once at genesis, **never again** → 0% inflation |
| Fees | real GMB fees (EIP-1559); **low but non-zero, scaling with usage** |
| License | code: Apache-2.0 · docs: CC BY-SA 4.0 |

## Repository layout

```
chain/       Cosmos EVM app (Go): app wiring, custom modules, genesis, config
contracts/   Solidity (Foundry): governor, treasuries, NFTs, paymaster
services/    Node.js/Express backends (on-ramp, access-control API, indexers)
frontend/    React
explorer/    Blockscout docker setup ("GembaScan")
docs/        Detailed specs & runbooks (see docs/risks.md)
```

## Conscious trade-offs & hard launch blockers

This is a real public chain with honestly-recorded risks. See
[`CLAUDE.md` §16](./CLAUDE.md) and the full ADRs in [`docs/risks.md`](./docs/risks.md).
**Public launch is blocked** until: (1) **MiCA** classification confirmed by a
Bulgarian fintech lawyer, (2) the upstream **Cosmos EVM audit** lands + our review,
and (3) the **security-budget tail reward** is implemented and bonded-ratio
monitoring is live.

## Secret hygiene

This repo is **public**. Never commit `.env`, private keys, mnemonics, node keys, or
DB passwords. Copy [`.env.example`](./.env.example) → `.env` and fill in locally;
`.gitignore` already excludes secrets and node data.

## Build status

Built in phases (see `CLAUDE.md` §13). Current: **Phase 0 — Scaffolding** (monorepo
structure, env/secret hygiene, docs). Next: **Phase 1 — Local devnet** from
`evmd`/`cosmos/evm`.
