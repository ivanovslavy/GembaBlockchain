# Runbook — raise the block gas limit (`block.max_gas`)

> **Finding (2026-06-06):** the chain's EVM block gas limit (`eth_getBlockByNumber.gasLimit`)
> is the CometBFT consensus param **`consensus_params.block.max_gas`**, set to **10,000,000**
> in genesis. That is too low for EVM workloads — a single contract deploy is ~4–5M and a
> CREATE2 pair deploy ~2.5M, so deploy+swap batches don't fit and tooling (forge) thrashes
> between OOG and "exceeds block gas limit". See `docs/risks.md` ADR-012.

## Fixed for new genesis (mainnet + future testnets)

`chain/scripts/lib.sh` now sets `block.max_gas = "100000000"` (100M, ~10× and ~3× Ethereum L1).
Any chain generated from the scripts gets 100M from block 0. **No further action needed for a
fresh genesis.**

## Raising it on the ALREADY-RUNNING `gemba-testnet-1` (governance)

Consensus params live in chain state, not re-read from genesis, so on a running chain they
change **only via an `x/consensus` `MsgUpdateParams` governance proposal**. This is a
shared-validator action — **run it deliberately / with operator sign-off.**

```bash
# proposal.json (authority = gov module account; keep all other params as-is, raise max_gas)
{
  "messages": [{
    "@type": "/cosmos.consensus.v1.MsgUpdateParams",
    "authority": "cosmos10d07y265gmmuvt4z0w9aw880jnsr700j6zn9kn",
    "block":     {"max_bytes": "22020096", "max_gas": "100000000"},
    "evidence":  {"max_age_num_blocks": "100000", "max_age_duration": "172800s", "max_bytes": "1048576"},
    "validator": {"pub_key_types": ["ed25519"]},
    "abci":      {"vote_extensions_enable_height": "0"}
  }],
  "deposit": "20000000agmb",
  "title": "Raise block.max_gas 10M -> 100M",
  "summary": "Raise the CometBFT block gas limit to support EVM deploys/DeFi."
}

# submit (from a node with a funded key) + vote with the validators (voting_period is 30s):
gembad tx gov submit-proposal proposal.json --from valop \
  --keyring-backend test --home /root/.gembad --chain-id gemba-testnet-1 \
  --node tcp://localhost:26657 --gas auto --gas-adjustment 1.6 --gas-prices 10000000000agmb -y
# get the id, then on EACH validator (>= 2/3 bonded for safety) within 30s:
gembad tx gov vote <ID> yes --from valop  <same flags>
# verify after ~30s:
gembad q gov proposal <ID> -o json | jq .proposal.status   # PROPOSAL_STATUS_PASSED
curl -s localhost:26657/consensus_params | jq .result.consensus_params.block.max_gas  # "100000000"
```

The 30s `voting_period` (devnet/testnet fast-iteration setting) is tight for multi-node
voting — script the votes to fire immediately after capturing the proposal id, or raise the
voting period first (a separate `x/gov` param-change proposal). After it passes, the new cap
applies to subsequent blocks and `forge script` deploys work at normal gas.

## Why not bigger / unlimited?

`max_gas = -1` (unlimited) is rejected: a single huge tx could stall block production
(liveness risk). 100M is a deliberate, governable cap — raise further by the same proposal
if real workloads need it.
