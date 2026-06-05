# Runbook — deploy gemba-testnet-1 (5 geo-separated validators)

A mainnet dress rehearsal: bring up `gemba-testnet-1` on the 5 Hetzner servers as
geographically separated validators. Practice everything here as if it were
mainnet. Local rehearsal first: `chain/testnet/init-local-testnet.sh` runs the whole
5-validator network on one host (verified to produce blocks).

Roles: one machine acts as **coordinator** (assembles the genesis); all 5 are
**validators**. Pick distinct regions (e.g. Nuremberg, Helsinki, Falkenstein, +2)
for real geo-separation.

## 0. Each machine: build the binary

```bash
# install Go + a C compiler + jq; then build the gembad node with our modules:
git clone https://github.com/ivanovslavy/GembaBlockchain && cd GembaBlockchain
./chain/gembad/build-gembad.sh           # -> $OUT (default /tmp/gembad); install to /usr/local/bin
```
Distribute one built binary to all 5 (same checksum) rather than building 5×.

## 1. Each validator: init + key + gentx

```bash
MONIKER=gemba-tn-val-<region>
gembad init "$MONIKER" --chain-id gemba-testnet-1 --home /var/lib/gemba
gembad keys add validator --keyring-backend file --algo eth_secp256k1 --home /var/lib/gemba
# self-bond account address (eth_secp256k1):
gembad keys show validator -a --keyring-backend file --home /var/lib/gemba   # -> send to coordinator
```
The coordinator funds each validator's account in genesis; then each validator makes
its gentx against the shared base genesis (coordinator distributes it after step 2a):

```bash
gembad genesis gentx validator 1000000000000000000000000agmb \
  --chain-id gemba-testnet-1 --keyring-backend file --home /var/lib/gemba
# send /var/lib/gemba/config/gentx/*.json to the coordinator
```

## 2. Coordinator: assemble & publish the canonical genesis

a. Build the **base genesis** with all funded accounts (the 5 validators + the drip
   faucet + reserves) and the GembaBlockchain economics. The simplest path is to run
   `chain/testnet/init-local-testnet.sh` once to produce a reference genesis, then
   replace the locally-generated validator accounts with the real ones — or script
   `genesis add-genesis-account` for each address and set the custom-module +
   feemarket + mint(0) params via `lib.sh patch_economics`. The drip faucet account
   `tnfaucet` is funded 20,000,000 test GMB (chain/testnet/testnet.params.sh).
b. Collect every validator's gentx and finalize:
   ```bash
   cp received-gentxs/*.json config/gentx/
   gembad genesis collect-gentxs --home <coord-home>
   gembad genesis validate-genesis --home <coord-home>
   sha256sum config/genesis.json     # publish this hash
   ```
c. **GENESIS FEE FIX — required (CLAUDE.md ADR-008a).** gentxs are zero-fee
   (`MsgCreateValidator` with no `--gas-prices`), but the cosmos `MinGasPriceDecorator`
   enforces `feemarket.min_gas_price` on **both** CheckTx and DeliverTx — so at
   `InitChain` it rejects the zero-fee gentxs ("minimum global fee … insufficient
   fee") and the node panics. The decorator **short-circuits when `min_gas_price`
   is 0**, so set it to 0 in genesis (the node's `minimum-gas-prices` and the EVM
   `base_fee` stay non-zero — genesis txs run in DeliverTx mode where the validator
   min-gas-price check is skipped, so they do NOT block genesis):
   ```bash
   jq '.app_state.feemarket.params.min_gas_price = "0.000000000000000000"' \
      config/genesis.json | sponge config/genesis.json
   gembad genesis validate-genesis --home <coord-home>
   sha256sum config/genesis.json     # THIS is the canonical hash to publish
   ```
   **ADR-008a is preserved for runtime and fully restored post-genesis:** `base_fee`
   stays 1 gwei and node `minimum-gas-prices` stays 1 gwei; once the chain is live,
   a governance `feemarket` param-change sets `min_gas_price` back to `1000000000…`
   to re-arm the consensus-level floor. (Alternatively, create gentxs WITH
   `--gas-prices 1000000000agmb` so they carry a fee — but that means regenerating
   gentxs; the min_gas_price=0 approach does not.)
d. **Publish** the canonical `genesis.json` (+ its sha256) and the **peer list**:
   `gembad comet show-node-id --home ...` on each node → `nodeid@public_ip:26656`.

## 3. Each validator: install genesis, peers, config

```bash
cp canonical-genesis.json /var/lib/gemba/config/genesis.json
sha256sum /var/lib/gemba/config/genesis.json    # MUST match the published hash
```
After installing the canonical genesis, **reset any prior data** so the node
InitChains fresh on it (keeps keys): `gembad comet unsafe-reset-all --home <home>`.

`config.toml`:
```toml
# [p2p]
persistent_peers = "<id1>@ip1:26656,<id2>@ip2:26656,..."   # the OTHER validators
seeds = "<seed_id>@seed_ip:26656"                          # 1-2 seed nodes
addr_book_strict = false        # REQUIRED on a private LAN (192.168.x) — strict
                                # mode rejects non-routable IPs from the address book
# [mempool]
type = "app"                    # REQUIRED by the EVM mempool (default "flood" panics)
```
`app.toml` (these were the per-node consistency fixes — set them on EVERY node):
```toml
minimum-gas-prices = "1000000000agmb"   # NOT the default "0aatom" (wrong denom);
                                        # this is the runtime node-level floor (ADR-008a)
evm-chain-id = 821207                    # testnet EVM chainId (default is 262144)
pruning = "custom"                       # validators prune (see node-setup.md)
```
Also `[telemetry] enabled = true` and CometBFT prometheus (`config.toml
[instrumentation]`; offset `prometheus_listen_addr` per host only if co-located).
Run **one** signer per validator; protect the consensus key (`validator-keys.md`,
tmkms recommended).

> The gentx `memo` may carry whatever IP the validator auto-detected at gentx time
> (often a different subnet) — it's only a hint. Always set `persistent_peers`
> explicitly with the correct addresses, as above.

## 4. Firewall & exposure (CLAUDE.md §11)

| Port | Who | Exposure |
|---|---|---|
| 26656 (P2P) | peers | open to the other validators/seeds |
| 26657 / 1317 / 8545 (RPC/REST/JSON-RPC) | public/apps | **behind Apache reverse proxy + Let's Encrypt (HTTPS) + rate-limit**, not raw |
| 26660 (Prometheus) | monitoring | internal/VPN only |

A **sentry topology** is recommended for validators (private P2P, public sentries).
Run the **drip faucet** (`services/testnet-faucet`) and one **archive node**
(`pruning = "nothing"`) for the explorer (`explorer/`) — the explorer points at the
archive node, never a pruned validator.

## 5. systemd

```ini
# /etc/systemd/system/gembad.service
[Unit]
Description=GembaBlockchain testnet validator
After=network-online.target
[Service]
User=gemba
ExecStart=/usr/local/bin/gembad start --home /var/lib/gemba --chain-id gemba-testnet-1 \
  --evm.evm-chain-id 821207 --minimum-gas-prices 1000000000agmb
Restart=on-failure
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
```
```bash
systemctl enable --now gembad && journalctl -u gembad -f
```

## 6. Verify launch

All 5 validators online, `gembad status` height advancing on each, 4 peers each,
validator set = 5. Then work through `testnet-launch-checklist.md`. Practice a
coordinated upgrade (`coordinated-upgrade.md`) and a halt recovery
(`halt-recovery.md`) on the testnet before relying on them for mainnet.
