# chain/gembad — the GembaBlockchain node (evmd + custom modules)

`gembad` is the node binary: the pinned upstream `cosmos/evm` reference app
(`evmd` v0.7.0) with the Phase 2 custom modules (`x/rewardstreamer`, `x/feesplit`)
wired into its module manager.

We do **not** vendor evmd into the repo. The build fetches the pinned reference
app and applies a small, version-pinned wiring patch, so the custom modules stay
isolated in `chain/x` and an upstream bump is just: re-clone the new tag, refresh
the patch (CLAUDE.md §16.6).

## Files

| File | Purpose |
|---|---|
| `gembad-wiring.patch` | the only app edits: `evmd/app.go` (store keys, keepers, module manager, begin-blocker order `feesplit → rewardstreamer → distribution`, init-genesis order) + `evmd/config/permissions.go` (module accounts `rewardstreamer`/`feesplit`/`faucet`, all with NO mint/burn permissions) |
| `build-gembad.sh` | clones cosmos/evm v0.7.0, applies the patch, `go mod replace`s to `chain/`, builds `gembad` |
| `init-gembad.sh` | single-node devnet; funds the 20M reserve + 30M faucet into the **module accounts** and sets the module genesis params |
| `init-gembad-multinode.sh` | 4-validator devnet (BFT, §5.3) |
| `demo-gembad.sh` | live demonstration: a real EVM transfer whose fee splits 60/40, with the supply-invariance check on the running chain |

## Quick start

```bash
export PATH="$PATH:$(go env GOPATH)/bin"
./build-gembad.sh                              # -> /tmp/gembad
GEMBAD=/tmp/gembad ./init-gembad.sh            # single-node genesis
/tmp/gembad start --home ~/.gembad-devnet --chain-id gemba-1 \
  --evm.evm-chain-id 821206 --minimum-gas-prices 1000000000agmb \
  --json-rpc.enable --json-rpc.api eth,net,web3,txpool,debug --api.enable &
GEMBAD=/tmp/gembad ./demo-gembad.sh            # the live fee-split + supply demo

# or the 4-validator BFT devnet:
GEMBAD=/tmp/gembad ./init-gembad-multinode.sh
EVMD=/tmp/gembad BASE=~/.gembad-multinode ../scripts/start-multinode.sh
GEMBAD=/tmp/gembad HOME_DIR=~/.gembad-multinode/node0 ./demo-gembad.sh
```

## What the live demo proves (on the real node, not in-process)

Verified on both single-node and 4-validator devnets:

- **Zero inflation (§3.1):** total supply stays exactly 100,000,000 GMB across
  blocks while ~1000 GMB/block (devnet-amplified) streams from the reserve.
- **60/40 fee split (§5.4):** a real EVM transfer paying a 2.1 GMB fee moves
  exactly 0.84 GMB (40%) into the faucet module account; the other 60% goes to
  validators via distribution.
- **Recirculation, not minting:** the reserve module account drains by exactly
  the streamed amount, and the supply delta is 0.

## Genesis gotcha (documented)

The reserve and faucet are **module accounts**. `add-genesis-account` would create
plain `BaseAccount`s at those addresses, which makes the bank keeper panic
(`account is not a module account`) the first time a module sends to/from them.
The init scripts therefore fund the addresses and then strip the `BaseAccount`
entries from `auth.accounts`; the module accounts are created lazily as proper
`ModuleAccount`s on first use and the genesis balances persist.

The reward stream also skips the very first block: at height 1 the distribution
module has no prior-block votes to allocate, so a height-1 reward would linger and
be skimmed by the next block's feesplit (leaking it to the faucet). From height 2
distribution drains the fee collector in the same block, so the reward reaches
validators in full. See `x/rewardstreamer/keeper/stream.go`.
