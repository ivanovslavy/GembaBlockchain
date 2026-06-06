# Runbook — corrected re-genesis of gemba-testnet-1 (exact §4.1 allocation)

> **Why (decided 2026-06-06, path A):** the live testnet genesis is testing-shaped and
> ~47% of supply sits in keyless Cosmos module accounts, so the reserve **contracts** can't
> be funded to their exact §4.1 %s (`docs/tokenomics-pending.md`). A corrected re-genesis is
> the clean fix and the proper mainnet dress rehearsal: each reserve held by its contract,
> at its exact %, under Governor+Timelock custody, with the gas-limit fix (100M) from block 0.
>
> **⚠️ Destructive:** this resets the chain to height 0 — it discards the current live state
> (the deployed GembaSwap DEX + demo contracts, and the explorer's indexed history) and
> re-inits the 4 validators. The testnet is valueless, so this is acceptable; **do it
> deliberately, with operator awareness of all 4 validator hosts.**

## Target allocation (100M, exact §4.1) — `chain/testnet/testnet.params.sh`

| EOA / module | GMB | Then transferred to | % |
|---|---|---|---|
| `faucetreserve` EOA | 30M | `Faucet` contract | 30 |
| `rewardstreamer` module | 20M | (stays — validator rewards) | 20 |
| `foundation` EOA | 15M | `FoundationTreasury` | 15 |
| `dao` EOA | 10M | `DAOReserve` | 10 |
| `contingency` EOA | 10M | `ContingencyReserve` | 10 |
| 5 validators × 2M | 10M | (circulation / self-bond) | 10 |
| `founder` EOA | 5M | (stays — non-voting) | 5 |

The testnet drip faucet draws from the `Faucet` contract via the §4.1 grant mechanism (no
separate drip allocation).

## Procedure

1. **Update `chain/testnet/init-local-testnet.sh`** to allocate the EOAs above with the new
   amounts — remove the faucet-module account and the separate 20M drip EOA; add a
   `faucetreserve` and `contingency` reserve EOA; foundation 10M→15M, contingency 5M→10M.
   (`testnet.params.sh` values are already updated.)
2. **Regenerate genesis** with the 4 current validators as genesis validators (re-use their
   consensus keys, or fresh gentxs). `chain/scripts/lib.sh` already sets `block.max_gas=100M`.
3. **On each of the 4 validators** (3 Contabo + node2): stop the service, back up the old
   data, `gembad comet unsafe-reset-all --home <H> --keep-addr-book`, install the new
   `genesis.json`, restart. The chain starts at height 0 with the new allocation.
4. **Re-deploy contracts** (now at 100M block gas, normal forge gas works):
   - Governance: `GembaVotes`, `GembaTimelock`, `GembaGovernor`, `EmergencyPause`.
   - Reserves (UUPS proxies): `Faucet`, `FoundationTreasury`, `DAOReserve`, `ContingencyReserve`
     — `initialize(owner=Timelock, pauser=EmergencyPause, …)`.
   - DEX: GembaSwap (`WGMB`, factory, router02), `GembaNativePoolFactory`, `LiquidityLocker`.
5. **Fund the reserves**: from each reserve EOA, transfer its FULL balance to its contract
   (faucetreserve→Faucet 30M, foundation→FoundationTreasury 15M, dao→DAOReserve 10M,
   contingency→ContingencyReserve 10M). Point `x/feesplit`'s 40% at the Faucet contract.
6. **Wire governance**: Timelock owns every reserve; Governor proposer; EmergencyPause
   guardians = elected accounts. Run a test proposal end-to-end.
7. **Verify every contract** on GembaScan (no API key: `forge verify-contract <CA> <C>
   --verifier blockscout --verifier-url https://testnet.gembascan.io/api/`).
8. **Re-point the explorer**: the archive node re-syncs from height 0; restart Blockscout so
   it re-indexes the fresh chain.
9. Record all CAs in `docs/testnet-deployments.md`.

## Mainnet

No re-genesis dance — generate the genesis once with this exact allocation (predeploy the
reserve contracts + allocate to them, or allocate to EOAs and fund in the launch runbook).
