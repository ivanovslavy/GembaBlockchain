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
c. **Publish** the canonical `genesis.json` (+ its sha256) and the **peer list**:
   `gembad comet show-node-id --home ...` on each node → `nodeid@public_ip:26656`.

## 3. Each validator: install genesis, peers, config

```bash
cp canonical-genesis.json /var/lib/gemba/config/genesis.json
sha256sum /var/lib/gemba/config/genesis.json    # MUST match the published hash
```
`config.toml [p2p]`:
```toml
persistent_peers = "<id1>@ip1:26656,<id2>@ip2:26656,..."   # the other 4 validators
seeds = "<seed_id>@seed_ip:26656"                          # 1-2 seed nodes
```
`app.toml`: `pruning = "custom"` (validators prune; see `node-setup.md`),
`minimum-gas-prices = "1000000000agmb"`, `evm-chain-id = 821207`, `[telemetry]
enabled = true`. Enable CometBFT prometheus (`config.toml [instrumentation]`).
Run **one** signer per validator; protect the consensus key (`validator-keys.md`,
tmkms recommended).

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
