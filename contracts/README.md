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
| `PublicReserve` | public/municipal reserve; intake of 40% of fees; formula + vesting grants; per-grant cap |
| `FoundationTreasury` | dev funding, released by governance |
| `DAOReserve` | contingency funds, released by governance |
| `ContingencyReserve` | holds the 10% contingency GMB (unforeseen needs; **no liquidity seeded — by design**, CLAUDE.md §8); released only by governance + timelock |
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
| `PublicReserve` | `src/reserves/PublicReserve.sol` | UUPS; receives feesplit's 40%; capped formula grants + governance `release` |
| `FoundationTreasury` / `DAOReserve` / `ContingencyReserve` | `src/reserves/` | UUPS reserves; release only by Timelock |
| `BaseReserve` | `src/reserves/BaseReserve.sol` | shared UUPS base: owner=Timelock, upgrade authority Timelock-only, Pausable |
| `EmergencyPause` | `src/governance/EmergencyPause.sol` | m-of-n guardian; **pause-only**, guardians replaceable by governance |
| *DEX dev tooling* | `src/dex/` | **optional, NOT project-operated**: `gembaswap/` = **official Uniswap V2 renamed 1:1** (full Router02) + `WGMB` + **pure-native `GembaNativePool`** + `LiquidityLocker`, for developers to deploy for their own ERC-20 tokens. See `src/dex/README.md`. |

Upgrade authority of every reserve is the **Timelock only, never an EOA**. The
Cosmos↔EVM seam is resolved (`SeamProbe.sol` + the resolution in
`docs/phase3-treasury-principles.md`): feesplit deposits native GMB straight into
the Faucet's address.

## Phase 4 — DONE (sponsored gas, meta-tx relay)

| Contract | File | Notes |
|---|---|---|
| `GembaForwarder` | `src/paymaster/GembaForwarder.sol` | EIP-2771 trusted forwarder; relayer pays gas, employee only signs (no GMB) |
| `WorkplaceCheckIn` | `src/paymaster/WorkplaceCheckIn.sol` | ERC2771Context demo target; attributes the action to the employee, not the relayer |

Meta-tx relay first (not ERC-4337 — faster start). The relayer is a per-institution
operational dependency, **not** a chain dependency, and the employee always keeps a
direct-submit fallback (`docs/risks.md` ADR-011). Live devnet demo
(`contracts/script/SponsoredDemo.s.sol` + `chain/gembad`): an employee with **0 GMB**
makes a successful tx whose gas the **sponsoring wallet** pays.

EIP-1559 fee tuning (chain-side) is demonstrated by `chain/gembad/demo-feemarket.sh`:
base fee at the 1 gwei floor when idle, scaling up under load, decaying after.

### Build & test

```bash
cd contracts
./setup-libs.sh                 # fetch pinned OpenZeppelin v5 + forge-std into lib/
forge test                      # 41 tests incl. invariant/fuzz + meta-tx suites
slither . --filter-paths "lib/|test/|script/" --exclude-dependencies   # triaged in SECURITY.md
```

## Phase 5 — DONE (access control)

| Contract | File | Notes |
|---|---|---|
| `AccessControlNFT` | `src/access/AccessControlNFT.sol` | soulbound ERC-1155 capability (token id = zone); issuer-gated grant/revoke; **no PII on-chain** (CLAUDE.md §10) |

Pairs with the off-chain backend `services/access-control` (PostgreSQL RLS + GDPR
split). 7 Foundry tests; Slither clean.

## Phase 6 — DONE (GembaPay on-ramp)

| Contract | File | Notes |
|---|---|---|
| `GembaOnRamp` | `src/onramp/GembaOnRamp.sol` | fixed-rate stablecoin→GMB sale (no DEX, no fiat redemption); SafeERC20 + `nonReentrant` |

**MiCA gate (ADR-009):** `publicSaleEnabled` is **false by default**; enabling public
sale on a public/main network is **blocked until written MiCA sign-off** from a
Bulgarian fintech lawyer (see the contract header + `docs/risks.md` ADR-009). Built
and tested on devnet only. 8 Foundry tests; live demo `script/OnRampDemo.s.sol`.

## Phase 8 — DONE (tickets & perks)

| Contract | File | Notes |
|---|---|---|
| `GembaTicketing` | `src/tickets/GembaTicketing.sol` | events as ERC-1155: create/issue/buy(GMB)/redeem; supply caps; organizer + scanner roles |
| `GembaPerks` | `src/tickets/GembaPerks.sol` | institution pays GMB bonuses + grants perk tickets; per-bonus cap |

24 Foundry tests incl. reentrancy + invariant/fuzz (minted ≤ maxSupply; perks pool
never over-drained); Slither triaged. Live demo `script/TicketingDemo.s.sol`.
