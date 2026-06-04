# /contracts — Solidity (Foundry)

Treasury, governance, and application contracts deployed on GembaBlockchain's EVM.
Use **Foundry** (preferred) or Hardhat. Upgradeable where governance must evolve
them (proxy + Timelock).

> Staking, slashing, chain-level governance, the validator reward streamer, the
> 60/40 fee split, and the tail reward are **Cosmos Go modules, not Solidity**
> (see `/chain`). Only treasuries and app logic live here.

## Contracts (CLAUDE.md §9)

| Contract | Responsibility |
|---|---|
| `Governor` + `Timelock` | treasury/contract governance; **1 GMB = 1 vote** excluding reserve contracts; quorum, supermajority, delay |
| `Faucet` | public/municipal reserve; intake of 40% of fees; formula + vesting grants; per-grant cap |
| `FoundationTreasury` | dev funding, released by governance |
| `DAOReserve` | contingency funds, released by governance |
| `LiquidityReserve` | holds the 10% liquidity GMB; released only by governance + timelock |
| `EmergencyPause` (multisig) | pause-only guardian; governance-elected, replaceable; **cannot move funds** |
| `AccessControlNFT` | ERC-721/1155 capability tokens for workplace access (no PII) |
| `Paymaster` | sponsored gas (meta-tx relay first; ERC-4337 later) |
| `Ticketing` | ERC-1155 event tickets — later phase |

Reserve-holding contracts are **explicitly excluded from `getVotes`** so reserves
never vote (`CLAUDE.md` §3.4, §7). This is the **treasury electorate**, distinct from
the bonded-stake **consensus electorate** (ADR-008b).

## Phase

Built in **Phase 3** (governance & treasuries), **Phase 4** (`Paymaster`),
**Phase 5** (`AccessControlNFT`), **Phase 8** (`Ticketing`). Phase 0 placeholder.
