# Reserve-contract funding — plan + the genesis-vs-spec reconciliation

> **Supply decision (2026-06-06): stays 100,000,000 GMB (100M).** A 100B increase was
> considered and **rejected**. The `CLAUDE.md` §4.1 proportions are authoritative.

## Target: each reserve held by its contract, at its §4.1 %

| Bucket | % | GMB (of 100M) | Held by |
|---|---|---|---|
| Public/Municipal Reserve | 30% | 30M | `Faucet` contract |
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
