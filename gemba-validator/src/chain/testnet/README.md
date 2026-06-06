# chain/testnet — gemba-testnet-1 (public testnet)

The public testnet: a **mainnet dress rehearsal**. Same node binary (`gembad`,
with the custom modules), same economics (zero inflation, EIP-1559 floor, reward
streamer / fee split / tail reward), but a **distinct chain-id and EVM chainId**,
**valueless tokens**, and a generous **drip faucet**.

| | mainnet (`gemba-1`) | testnet (`gemba-testnet-1`) |
|---|---|---|
| Cosmos chain-id | `gemba-1` | `gemba-testnet-1` |
| EVM chainId | `821206` | `821207` |
| token value | real (utility) | **none** |
| faucet | institutional Faucet contract | open **drip faucet** (`services/testnet-faucet`) |
| unbonding | 14–21 days | 3 days (faster iteration) |

## Files

| File | Purpose |
|---|---|
| `testnet.params.sh` | testnet constants (ids, validators, allocation incl. 20M drip faucet) |
| `init-local-testnet.sh` | generate + run all 5 validators on ONE host (the rehearsal) |

## Local rehearsal (verified)

```bash
GEMBAD=/path/to/gembad ./init-local-testnet.sh   # builds gemba-testnet-1 genesis + 5 nodes
# start each: gembad start --home ~/.gemba-testnet/nodeN --chain-id gemba-testnet-1 ...
```
Verified: a valid 100,000,000 test-GMB genesis with 5 gentxs that **produces blocks**
(5 validators, 4 peers each) — the canonical genesis to distribute is
`~/.gemba-testnet/node0/config/genesis.json`.

## Real multi-machine deploy

The 5 geo-separated Hetzner validators: see
[`docs/runbooks/testnet-deploy.md`](../../docs/runbooks/testnet-deploy.md) (per-node
init + gentx, coordinator collect, seeds/persistent_peers, firewall, systemd) and
[`docs/runbooks/testnet-launch-checklist.md`](../../docs/runbooks/testnet-launch-checklist.md)
(what to watch the first weeks). Pair with the drip faucet
([`services/testnet-faucet`](../../services/testnet-faucet)) and an archive node for
the explorer.
