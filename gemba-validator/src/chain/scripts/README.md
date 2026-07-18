# chain/scripts — shared genesis anchors + devnet runners

**Current role (gembad era):** this dir holds the **shared genesis economics**
(`gemba.params.sh` + `lib.sh`) that every init path sources — the `chain/gembad/*`
devnet/mainnet builders and `chain/testnet/*` — plus the generic multi-node
start/stop runners that `chain/gembad` reuses (`EVMD=/tmp/gembad BASE=… ./start-multinode.sh`).

The Phase-1 **vanilla-`evmd` init scripts** (`init-single-node.sh`,
`init-multinode.sh`, `start-single-node.sh`) were removed in the 2026-07-19
mainnet cleanup — superseded by `chain/gembad/init-gembad*.sh`, which build the
wired `gembad` binary (custom modules included) instead of upstream `evmd`.
They live in git history if ever needed.

## Files

| File | Purpose |
|---|---|
| `gemba.params.sh` | **The genesis economic anchors** — every value cites the CLAUDE.md §/ADR it enforces |
| `lib.sh` | shared helpers: `patch_economics` bakes the anchors into `genesis.json`; `tune_cometbft` |
| `start-multinode.sh` / `stop-multinode.sh` | start / stop the 4-node devnet (node0 exposes JSON-RPC 8545); binary/base dir overridable via `EVMD`/`BASE` — this is how the gembad devnet runs |

## Quick start (gembad devnet)

```bash
cd ../gembad
./build-gembad.sh                # fetches pinned cosmos/evm + applies the Gemba wiring patch
./init-gembad-multinode.sh       # 4-validator BFT devnet (tolerates 1 down)
EVMD=/tmp/gembad BASE=~/.gembad-multinode ../scripts/start-multinode.sh
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

## DEVNET-ONLY test keys (conscious, bounded exception to CLAUDE.md §3)

The devnet init paths use the **public, well-known cosmos/evm test mnemonics**
(the same ones committed in upstream `local_node.sh`) with the `test` keyring,
purely so the devnet and the MetaMask/Foundry demos are reproducible. These are
published test vectors with **zero value — not secrets**. CLAUDE.md §3's
prohibition on committing keys/mnemonics targets **real** secrets and remains
fully in force: no real keys, no `.env`, and node keyrings/`.gembad`-style data
live outside the repo (in `$HOME/.gemba-*`) and are git-ignored. **Never** use
these keys or the `test` keyring on a public network.
