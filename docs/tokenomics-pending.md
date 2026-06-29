# Reserve-contract funding — plan + the genesis-vs-spec reconciliation

> **Supply decision (2026-06-06): stays 100,000,000 GMB (100M).** A 100B increase was
> considered and **rejected**. The `CLAUDE.md` §4.1 proportions are authoritative.

## Target: each reserve held by its contract, at its §4.1 %

| Bucket | % | GMB (of 100M) | Held by |
|---|---|---|---|
| Public/Municipal Reserve | 30% | 30M | `PublicReserve` contract |
| Validator Rewards | 20% | 20M | `rewardstreamer` Cosmos module (not a Solidity contract) |
| Foundation | 15% | 15M | `FoundationTreasury` contract |
| DAO Reserve | 10% | 10M | `DAOReserve` contract |
| Contingency Reserve (was Liquidity) | 10% | 10M | `ContingencyReserve` contract |
| Circulation | 10% | 10M | circulating EOAs (voting base) — not a contract |
| Founder/Ops | 5% | 5M | founder EOA (non-voting) — not a contract |

So **4 Solidity contracts** must end up holding 30 + 15 + 10 + 10 = **65M** under
Governor+Timelock custody.

## ⚠️ Why the live testnet can't be funded to these %s as-is

The `gemba-testnet-1` genesis (`chain/testnet/testnet.params.sh`) is **deliberately
testing-shaped, not the mainnet §4.1 shape**: drip-faucet EOA 20M + faucet **module** 20M
(40% total), validator-rewards **module** 20M, foundation 10M, dao 10M, liquidity 5M,
founder 5M, circulation 10M (validators). Two problems for accurate funding:

1. **~47M sits in keyless Cosmos module accounts** (rewardstreamer 20M, faucet module 20M,
   staking pools ~7M) — those can't be moved into Solidity contracts by transfer.
2. The **movable EOA balances (~55M) < the 65M** the four contracts need, and the per-bucket
   amounts don't match §4.1 (foundation 10M not 15M, contingency 5M not 10M).

**Conclusion: the live contracts cannot be funded to the exact §4.1 %s without a corrected
re-genesis.**

## Decision needed — two paths

- **(A) Corrected re-genesis** *(clean, accurate, the proper mainnet dress rehearsal).*
  Regenerate `gemba-testnet-1` with the §4.1 allocation (EOAs holding the exact reserve
  amounts, or contracts predeployed+funded), then deploy + fund the reserve contracts to
  exact %s. **Cost:** disruptive — resets chain height, re-inits the 4 validators, re-deploys
  the live DEX, and the explorer re-indexes from 0.
- **(B) Fund-as-available on the current chain** *(no re-genesis, approximate).* Deploy the
  contracts and fund each from its corresponding EOA with what's movable; document the
  **actual** % each contract ends up with and the deviation from §4.1. Reserves still move to
  governance custody for the parts that are movable; the module-locked portions stay as-is.

For **mainnet**, neither problem exists — the genesis is generated correctly from the start
(set the EOA/contract allocation to the §4.1 %s; `chain/scripts/lib.sh` already has the
gas-limit fix). Prefer genesis-predeploying the reserve contracts (bytecode in genesis) +
allocating to them directly, or allocate to EOAs and fund the contracts in the launch runbook.

## Tasks once a path is chosen

1. Deploy `GembaVotes`, `GembaTimelock`, `GembaGovernor`, `EmergencyPause` + the 4 reserves
   (UUPS proxies), wiring owner = Timelock, pauser = EmergencyPause.
2. Fund the 4 reserve contracts (path A: exact %s; path B: as-available + documented).
3. **Verify every deployed contract** on GembaScan (no API key needed).
4. Set up DAO/governance with the genesis wallets (Votes wrapping, a test proposal flow).

---

## ✅ MAINNET token distribution — EXACT (locked plan, 2026-06-29)

100,000,000 GMB, minted once at genesis, 0% inflation forever. At **mainnet launch** every
bucket is placed in its FINAL home at block 0 — no key-less module limbo, no post-launch
migration (the lesson from the testnet, where the 30M faucet ended up stuck in a key-less
Cosmos module — see the fix section below).

| # | Bucket | GMB | Where at genesis (block 0) | Controlled by | Votes? |
|---|---|---:|---|---|---|
| 1 | **Public Reserve** (public/municipal) | 30,000,000 | **PublicReserve CONTRACT** (predeployed via CREATE2, GMB allocated straight to its address) | Timelock (`release`, uncapped) + capped `granter` (formula) + EmergencyPause (pause-only) | No (excluded) |
| 2 | Validator reward reserve | 20,000,000 | `rewardstreamer` Cosmos module account | the module — auto-streams ~2M/yr, 0% inflation | No |
| 3 | Foundation | 15,000,000 | `FoundationTreasury` contract | Governor + Timelock | No (excluded) |
| 4 | DAO reserve | 10,000,000 | `DAOReserve` contract — **also a source for early-participant grants** | Governor + Timelock | No (excluded) |
| 5 | Contingency | 20,000,000 | `ContingencyReserve` contract — **absorbs the former 10M circulation pool (2026-06-29)** | Governor + Timelock | No (excluded) |
| 6 | Founder — ops & sale | 5,000,000 | founder EOA. From day 1 the founder seeds the OPEN channels from its **own** 5M (the 30M Public Reserve untouched): **100k → public faucet (GembaFaucet), 160k → GembaOnRamp sale, ~40k → the 4 validators**; keeps ~4.7M | founder | No (excluded) |

**No standing circulation pool** (decision 2026-06-29). GMB reaches anyone via OPEN channels seeded
by the founder's own 5M on day 1 — a **public faucet** (100k, `GembaFaucet`, anyone claims a little),
a **public on-ramp sale** (160k, `GembaOnRamp`, GMB for USE: Gemba dApps @20% off + validator entry,
non-commercial/for-society), the **4 validators** (~40k, permissionless), plus formula grants from the
Public Reserve and ecosystem grants from the DAO reserve. The `GembaFaucet`/`GembaOnRamp` contracts are
tested and funded day 1; nothing is hoarded.

**Genesis mechanics (the fixes vs the testnet):**
1. **Predeploy the 4 reserve contracts in genesis** (bytecode + CREATE2) and **allocate GMB
   directly to the contract addresses** → the 30M faucet lives in the PublicReserve CONTRACT from
   block 0, not a key-less module. No migration, no stuck funds.
2. **`feesplit.faucet_account` → the PublicReserve CONTRACT address** so the 40% fee inflow flows
   straight into the contract (requires the code fix below).
3. **All 4 reserve contracts + the founder excluded from `GembaVotes` at genesis** (invariant
   §3.4 — reserves never vote; closes the testnet defense-in-depth gap).
4. Reserve contracts: owner = Timelock, pauser = EmergencyPause, UUPS upgrade authority = Timelock.

Result: 30+15+10+20 = **75M in Governor+Timelock contracts**, 20M in the rewardstreamer module,
5M founder (non-voting; seeds the validators + early participants). No standing circulation pool —
voting GMB enters circulation only as the founder/DAO distribute it. 100M total — every coin
accounted for and publicly verifiable on addresses.gembachain.io + GembaScan.

## 🔧 Faucet / feesplit code fix (DECISION — required for the above; decision after vote)

**Problem (testnet, verified live 2026-06-29):** the 30M faucet reserve sits in a **key-less
Cosmos `faucet` module account** (`0xf40b…`), and `feesplit.faucet_account` is hard-validated to
point ONLY at that module (`DefaultFaucetAccount`, `chain/x/feesplit/types/params.go`). So both
the 30M genesis reserve AND the 40% fee inflow land in a module with **no withdraw path** —
module accounts are send-blocked and there is no faucet-keeper disbursement, so **a plain
governance vote cannot move them out**. Safe (no private key) but stuck. The EVM `PublicReserve` contract
(`0x9406…` on testnet) is deployed, **Timelock-owned** and governance-ready but holds **0 GMB**.

**Fix:**
- Relax `feesplit` `Params.Validate` so `FaucetAccount` may be **either** the registered module
  account **or a contract address**, and have the keeper deposit to whichever is set → the 40%
  then flows into the `PublicReserve` contract (which already expects it — `src/reserves/PublicReserve.sol`
  NatSpec). This is the mainnet design (and a clean testnet behaviour going forward).
- **Moving the existing testnet 30M out of the module is NOT a plain spend vote** — it requires a
  governance-voted **`MsgSoftwareUpgrade`** whose handler does a one-time faucet-module →
  PublicReserve-contract transfer (a coordinated node-operator upgrade). Otherwise leave the 30M key-less
  (safe) and fund the contract correctly at the next regenesis / at mainnet genesis.
