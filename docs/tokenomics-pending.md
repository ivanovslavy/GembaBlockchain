# ⚠️ PENDING — tokenomics rework (do NEXT session, not done yet)

> Decided 2026-06-06, **implementation deferred to the next session.** Nothing below
> is applied yet — the live `gemba-testnet-1` still has the OLD genesis (100M, mismatched
> proportions). This file is the brief for the next session.

## Decision: supply → **100B GMB** on BOTH networks

`N = 100,000,000,000 GMB` (100 billion), for **testnet AND mainnet**. Replaces the old
`100,000,000` (100M). Proportions stay the same **in %** (see tables). `CLAUDE.md §4.1`
must be updated from 100M → 100B.

## Mainnet allocation (100B) — the 7 buckets (§4.1, % unchanged)

| # | Bucket | % | GMB | Purpose |
|---|---|---|---|---|
| 1 | **Public/Municipal Reserve** (was called "faucet" in §4.1) | 30% | 30B | grants to institutions by formula + vesting; refilled by 40% of fees |
| 2 | Validator Rewards Reserve | 20% | 20B | zero-inflation rewards (~10y stream via `x/rewardstreamer`) |
| 3 | Foundation | 15% | 15B | dev/audits via governance |
| 4 | **DAO Reserve (contingency)** | 10% | 10B | **unforeseen needs** ("непредвидени") — governance-released |
| 5 | **Contingency Reserve** (*резерв непредвиден*) | 10% | 10B | unforeseen/strategic needs (replaces the former Liquidity Reserve — **no liquidity by design**, §8). NB: overlaps the DAO contingency #4 — decide whether to merge into one 20% bucket |
| 6 | Circulation pool | 10% | 10B | day-0 liveness + neutral voting base |
| 7 | Founder/Ops | 5% | 5B | working capital (sold for stablecoin, recirculates) |

> **Clarified naming gotcha:** there are TWO different 10% buckets — **DAO Reserve** =
> contingency/unforeseen; **Circulation** = day-0 liveness/voting. Don't conflate them.
> Also rename §4.1 bucket #1 from "faucet" to **Public/Municipal Reserve** to avoid
> confusion with the testnet *drip* faucet (a separate thing).

## Testnet allocation (100B) — **mirror of mainnet** (user's choice) + drip faucet

Same 7-bucket %s, but bucket #1's role (public distribution) is played by the **drip
faucet** (`services/testnet-faucet`, hands out valueless test GMB) instead of formula
grants: drip-faucet 30B, validator-rewards 20B, foundation 15B, DAO 10B, contingency 10B,
circulation 10B, founder 5B. Mirrors mainnet so the real governance/treasury flows can be
tested before mainnet. (No liquidity bucket — GembaBlockchain provides no liquidity by
design, §8.)

## Two OPEN decisions — confirm with the user before regenerating genesis

1. **Mainnet Public/Municipal Reserve (30%)** — user said "faucet не ми трябва на mainnet."
   That bucket IS the heart of the GembaBlockchain vision (institutional grants), distinct
   from the testnet drip faucet. **Confirm: keep it (recommended, just rename) or drop it
   (then redistribute the 30%)?**
2. **Testnet foundation** — user said "foundation не ми трябва на testnet" but chose
   "mirror mainnet" (which includes it). **Confirm: include a test foundation bucket, or
   drop it from testnet?**

## Two problems this rework must also FIX (found this session)

1. **Current testnet genesis ≠ spec.** Live chain has foundation 10M (spec 15%), a
   `liquidity` EOA 5M (the liquidity reserve is now **removed** → its 10% becomes a
   contingency reserve), **founder 9M (spec 5% — too high!)**, and the faucet split awkwardly
   across a `tnfaucet` EOA + a `faucet` module. The genesis generator (`chain/testnet`) put
   different numbers than `CLAUDE.md §4.1`. The 100B regen must align to the agreed %s.
2. **Reserves are NOT held by the governance contracts.** The native GMB sits in EOA genesis
   accounts (`tnfaucet/foundation/dao/liquidity/founder`) + Cosmos module accounts
   (`rewardstreamer`, `faucet`, staking pools) — NOT in `Faucet.sol`/`FoundationTreasury.sol`/
   `DAOReserve.sol`/`LiquidityReserve.sol` (which aren't deployed at all on 821207). So the
   "governance + timelock controls the reserves" model is NOT active — reserves are key-
   controlled EOAs (the documented §16.9 "de-facto centralized at genesis"). Intended fix:
   deploy the reserve/governance contracts, then **fund them** (transfer EOA → contract
   address) so they custody the reserves under Governor+Timelock. On mainnet the cleaner
   path is **genesis-predeploying** the contracts (bytecode in genesis state) + allocating
   directly to their addresses.

## Tasks for the next session (in order)

1. Get the user's answers to the two open decisions above.
2. Update `CLAUDE.md §4` (and §1 if needed): 100M → 100B, rename bucket #1 to
   Public/Municipal Reserve, keep the clarified DAO-vs-Circulation note.
3. Regenerate **both** genesis files (`chain/testnet` + the mainnet genesis plan) at 100B
   with the agreed proportions → new chain-id / fresh testnet (genesis change = restart).
4. Deploy the governance + reserve contracts on the (new) testnet and **verify** them
   (no API key needed — Blockscout verification is open). Then fund them EOA→contract to
   demonstrate the real governance-custody tokenomics.
5. Decide mainnet approach: genesis-predeploy contracts vs EOA-then-migrate.
