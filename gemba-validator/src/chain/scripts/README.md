# chain/scripts — GembaBlockchain local devnet (Phase 1)

Brings up a local devnet from the **pinned upstream `cosmos/evm` `evmd` binary**
(v0.7.0), with GembaBlockchain's genesis economics baked in. No Go code is
forked yet — Phase 1 configures genesis + node; the custom Go modules come in
Phase 2 (CLAUDE.md §13).

## Prerequisites

1. Build the pinned binary once:
   ```bash
   git clone --branch v0.7.0 https://github.com/cosmos/evm
   cd evm && make install          # installs evmd to $(go env GOPATH)/bin
   export PATH="$PATH:$(go env GOPATH)/bin"
   ```
   (Needs Go ≥ the version in cosmos/evm `go.mod`, a C compiler for CGO, and `jq`.)
2. For the transfer / deploy demos: [Foundry](https://book.getfoundry.sh) (`cast`, `forge`).

## Files

| File | Purpose |
|---|---|
| `gemba.params.sh` | **The genesis economic anchors** — every value cites the CLAUDE.md §/ADR it enforces |
| `lib.sh` | shared helpers: `patch_economics` bakes the anchors into `genesis.json`; `tune_cometbft` |
| `init-single-node.sh` | initialize a 1-node devnet (`$HOME/.gemba-devnet`) |
| `start-single-node.sh` | start it (EVM JSON-RPC on 8545) |
| `init-multinode.sh` | initialize 4 validators (`$HOME/.gemba-multinode/node{0..3}`) — BFT (§5.3) |
| `start-multinode.sh` / `stop-multinode.sh` | start / stop all 4 (node0 exposes JSON-RPC 8545) |

## Quick start

```bash
# single node
./init-single-node.sh && ./start-single-node.sh

# 4-validator BFT devnet (tolerates 1 down)
./init-multinode.sh && ./start-multinode.sh
```

## Where each genesis anchor lives (CLAUDE.md / docs/risks.md)

| Anchor | Spec | Set in |
|---|---|---|
| Cosmos chain-id `gemba-1` | §1 | `init --chain-id`, `gemba.params.sh` |
| EVM chainId `821206` (separate) | §1 | `app.toml [evm] evm-chain-id`, `--evm.evm-chain-id` |
| `eth_secp256k1` / coin type 60 → 0x addrs | §1 | `KEYALGO`, evmd default |
| GMB denom `agmb`, 18 decimals, display GMB | §1, §4 | `patch_economics` (denom + bank metadata) |
| **Mint inflation = 0** (no minting after genesis) | §3.1, §4.2, ADR-008 | `patch_economics` (mint params → 0) |
| **Fees low but NON-ZERO, scaling with usage** | §16.8, ADR-008a | `feemarket.min_gas_price` floor + `app.toml minimum-gas-prices` (both 1 gwei) |
| ~2 s blocks | §1, §11 | `tune_cometbft` (`timeout_commit`) |
| Active-set cap 100 | §5.2 | `staking.max_validators` |
| Fixed supply 100M GMB, §4.1 buckets | §4.1 | `gemba.params.sh` ALLOC_* + genesis accounts |
| Reserves non-voting | §3.4, §7 | reserves funded but never staked; only circulation self-bonds |

**Not yet implemented (by design):** the post-year-10 **tail reward**
(ADR-008 mechanism (b), recirculation-funded, never minted) and the **60/40 fee
split** are Phase 2 custom Go modules. Scope is reserved; do not fake them with
minting. See `chain/README.md`.

## DEVNET-ONLY test keys (conscious, bounded exception to CLAUDE.md §3)

The scripts use the **public, well-known cosmos/evm test mnemonics** (the same
ones committed in upstream `local_node.sh`) with the `test` keyring, purely so
the devnet and the MetaMask/Foundry demos are reproducible. These are published
test vectors with **zero value — not secrets**. CLAUDE.md §3's prohibition on
committing keys/mnemonics targets **real** secrets and remains fully in force:
no real keys, no `.env`, and node keyrings/`.gembad`-style data live outside the
repo (in `$HOME/.gemba-*`) and are git-ignored. **Never** use these keys or the
`test` keyring on a public network.
