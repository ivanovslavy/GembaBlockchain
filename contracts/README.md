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

## Phase 3 — DONE (governance & treasury contracts)

Implemented in `src/` (OpenZeppelin v5), with `tests first, funding last`
(`docs/phase3-treasury-principles.md`): **all contracts are unfunded**; reserves
require an audit before mainnet genesis.

| Contract | File | Notes |
|---|---|---|
| `GembaVotes` (vGMB) | `src/governance/GembaVotes.sol` | 1-GMB-1-vote: ERC20Votes wrapper of native GMB; reserves excluded (can't hold it, 0 votes) |
| `GembaTimelock` | `src/governance/GembaTimelock.sol` | TimelockController; owns every reserve; open execution after delay |
| `GembaGovernor` | `src/governance/GembaGovernor.sol` | high quorum + **supermajority** (66–75%) + timelock |
| `Faucet` | `src/reserves/Faucet.sol` | UUPS; receives feesplit's 40%; capped formula grants + governance `release` |
| `FoundationTreasury` / `DAOReserve` / `LiquidityReserve` | `src/reserves/` | UUPS reserves; release only by Timelock |
| `BaseReserve` | `src/reserves/BaseReserve.sol` | shared UUPS base: owner=Timelock, upgrade authority Timelock-only, Pausable |
| `EmergencyPause` | `src/governance/EmergencyPause.sol` | m-of-n guardian; **pause-only**, guardians replaceable by governance |

Upgrade authority of every reserve is the **Timelock only, never an EOA**. The
Cosmos↔EVM seam is resolved (`SeamProbe.sol` + the resolution in
`docs/phase3-treasury-principles.md`): feesplit deposits native GMB straight into
the Faucet's address.

### Build & test

```bash
cd contracts
./setup-libs.sh                 # fetch pinned OpenZeppelin v5 + forge-std into lib/
forge test                      # 36 tests incl. invariant/fuzz suites
slither . --filter-paths "lib/|test/" --exclude-dependencies   # findings triaged in SECURITY.md
```

## Later phases

`Paymaster` (Phase 4), `AccessControlNFT` (Phase 5), `Ticketing` (Phase 8).
