# Mainnet GembaVotes exclusion list — "only validators vote at launch"

> **THE highest-severity launch item** (`docs/mainnet-launch-hardening.md` §B). vGMB
> (`GembaVotes`) is a 1:1 wrapper over native GMB with supply starting at 0 — voting power
> exists only for addresses that wrap. Excluding **every genesis-seeded holder** therefore
> leaves Cosmos bonded stake (the validators, via `x/gov`) as the only voice until GMB
> legitimately circulates (faucet drips, dispenser sales, grants). Decision: owner, 2026-07-17.

## How it is applied

`contracts/script/DeployGovernance.s.sol` excludes the **4 reserve contracts automatically**
(PublicReserve, FoundationTreasury, DAOReserve, ContingencyReserve) and appends everything in
the `EXCLUDE_EXTRA` env var (comma-separated `0x…` list). Parsing is **strict** — any malformed
entry reverts the deploy (a typo cannot silently exclude nobody; covered by
`test/DeployGovernanceExclusions.t.sol`). After the deploy, run
`contracts/script/verify-exclusions.sh` (below) — it must print all-OK **before** the launch
is announced.

## The list (fill the addresses at the key ceremony — they do not exist before it)

Every address the mainnet genesis funds, plus the operational GMB-holding contracts:

| # | Role | Address (fill at ceremony) | Why excluded |
|---|---|---|---|
| auto | PublicReserve contract | CREATE2-fixed | reserve — never votes (§3.4) |
| auto | FoundationTreasury contract | CREATE2-fixed | reserve — never votes |
| auto | DAOReserve contract | CREATE2-fixed | reserve — never votes |
| auto | ContingencyReserve contract | CREATE2-fixed | reserve — never votes |
| 1 | Founder EOA (`FOUNDER_ADDR`) | `0x________` | founder never votes (§3.5); holds ~4.86M |
| 2 | Foundation genesis EOA | `0x________` | carries 15M until the reserve contract is funded |
| 3 | DAO genesis EOA | `0x________` | carries 10M until funded |
| 4 | Contingency genesis EOA | `0x________` | carries 20M until funded |
| 5 | Public-faucet seed EOA | `0x________` | carries the 100k drip-faucet seed |
| 6 | Validator 0 EOA | `0x________` | founder-run at genesis; consensus power ≠ treasury power (§5.7) |
| 7 | Validator 1 EOA | `0x________` | — " — |
| 8 | Validator 2 EOA | `0x________` | — " — |
| 9 | Validator 3 EOA | `0x________` | — " — |
| 10 | `GembaPayDispenser` | CREATE2/deploy addr | holds the sale stock — must never carry votes |
| 11 | `GmbCollector` | deploy addr | accumulates dApp payments |
| 12 | `GembaDripFaucet` | deploy addr | holds the 100k public-faucet pool |

The Cosmos **module** accounts (rewardstreamer 20M reserve, feesplit "faucet" 30M Public
Reserve) have no EVM key and cannot call `depositFor` — no exclusion entry needed; noted here
so the review doesn't flag them as missing.

`EXCLUDE_EXTRA` = rows 1–12 joined with commas (rows 10–12 can also be excluded post-deploy
via a governance `setExcluded` if their deploy order makes them unknown at governance-deploy
time — do NOT skip them, schedule the proposal).

## Verification (mandatory, scripted)

```
VOTES=<GembaVotes addr> RPC=<mainnet rpc> LIST=<file with one 0x address per line> \
  contracts/script/verify-exclusions.sh
```

The script asserts for every list entry: `excluded(addr) == true` **and** `getVotes(addr) == 0`,
plus a negative control (a fresh address is NOT excluded — the wrapper stays permissionless
for the public). Record its output in the launch log.
