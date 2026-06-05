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

## 5. Durable setup with systemd (survives reboot — verified)

Goal: after a reboot of any machine, its node comes back **automatically** and
rejoins, with no manual step.

**a. Put the binary on a persistent path.** `/tmp` is wiped on reboot, so never run
the node from `/tmp/gembad`. Install to `/usr/local/bin` on every machine:
```bash
sudo cp /tmp/gembad /usr/local/bin/gembad && sudo chmod 755 /usr/local/bin/gembad
hash -r && gembad version --long      # confirm it resolves with no full path
```
Build with version ldflags if you want `gembad version` to print a tag (the bare
`build-gembad.sh` leaves it blank; the binary still works — the sha256 is the
identity, see §0).

**b. Keep all node data under the home in `/home`** (`~/.gembad-testnet-nodeN`),
never in `/tmp`. Confirm `config/genesis.json`, `config/priv_validator_key.json`,
`config/node_key.json` and `data/` all live under the home.

**c. The unit.** `WorkingDirectory` is **required** — systemd's default CWD is `/`,
which the service user cannot write, and the node creates a relative `data` dir at
startup → `mkdir data: permission denied` crash-loop. Set it to the node home:
```ini
# /etc/systemd/system/gembad.service     (set --home / WorkingDirectory per machine)
[Unit]
Description=GembaBlockchain testnet validator (gemba-testnet-1)
After=network-online.target
Wants=network-online.target
[Service]
User=slavy
WorkingDirectory=/home/slavy/.gembad-testnet-node0
Environment=HOME=/home/slavy
ExecStart=/usr/local/bin/gembad start --home /home/slavy/.gembad-testnet-node0 \
  --chain-id gemba-testnet-1 --evm.evm-chain-id 821207 \
  --minimum-gas-prices 1000000000agmb --json-rpc.enable=false
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
```

**d. Enable + switch off any manual process** (avoid two signers on one home):
```bash
sudo systemctl daemon-reload && sudo systemctl enable gembad
# stop any nohup/foreground node BY THE BINARY (not 'pkill -f "gembad start"',
# which also matches your own shell): kill the process whose comm is gembad:
for p in $(ps -eo pid,comm | awk '$2=="gembad"{print $1}'); do sudo kill -9 "$p"; done
sudo systemctl start gembad
systemctl is-active gembad && systemctl is-enabled gembad
```

## 6. Verify launch + reboot test

Bring-up: every validator `active`+`enabled`, height advancing, peers = N−1 each,
identical app hash. Then **prove durability with a real reboot** (not just
`enable`):
```bash
ssh <node> 'sudo reboot'        # SSH drops — expected
# wait for it to return, then:
ssh <node> 'systemctl is-active gembad; curl -s localhost:26657/status \
  | jq "{h:.result.sync_info.latest_block_height, catching_up:.result.sync_info.catching_up}"'
```
Expect: `gembad` already `active` on a fresh boot (uptime ~0 min), peers reconnected,
`catching_up:false`, height in sync with the others. *(Verified on the i3 node: after
`sudo reboot` it came back in ~60s, the service auto-started, rejoined both peers and
re-synced — no manual action.)*

> **BFT liveness note.** With **3 equal-stake** validators, any single one offline
> drops the set to exactly 2/3 — not the **strictly >2/3** CometBFT needs to commit
> — so the chain **pauses** while a node reboots and resumes the moment it rejoins.
> That is expected for n=3. To tolerate one node down (no pause), run **≥4**
> validators (the Hetzner target is 5, §5.3) — then a reboot is fully seamless.

Finally work through `testnet-launch-checklist.md`, and rehearse a coordinated
upgrade (`coordinated-upgrade.md`) and halt recovery (`halt-recovery.md`).

## 7. Adding a validator to a LIVE network (permissionless dynamic join)

A new validator joins a running chain by syncing as a full node, then sending a
`MsgCreateValidator` — no genesis change, no coordination. This is the permissionless
entry of §5.2. *(Verified: a 4th node joined the live 3-validator testnet, entered the
active set, and signed every block.)*

**a. Fresh, independent node — never reuse keys.**
```bash
H=/home/slavy/.gembad-testnet-node3
gembad init gemba-tn-val-node3 --chain-id gemba-testnet-1 --home "$H"   # fresh consensus + node key
gembad keys add node3val --keyring-backend test --algo eth_secp256k1 --home "$H"
```
> **CRITICAL:** the new node MUST have its **own** `priv_validator_key.json` and
> `node_key.json`. A shared consensus key = **double-signing = slash + tombstone**
> (§5.6). Verify the consensus pubkey differs from every existing node:
> `gembad comet show-validator --home "$H"` (and `show-node-id`).

**b. Co-located on an existing node's machine?** (e.g. a 2nd validator on one host —
not the Hetzner layout, where each is its own host). Then **offset every port** in
`config.toml`/`app.toml` (p2p/rpc/proxy_app/grpc/json-rpc/api/pprof/prometheus, e.g.
`26666/26667/26668/9091/8555/1327/6061/26670`), use a distinct systemd unit name
(`gembad-node3.service`), and set **`allow_duplicate_ip = true`** on the peers it
connects to — otherwise they reject it as a duplicate of the IP they already peer
with (same machine), and it can't gossip its votes. (On separate hosts, none of this
applies.)

**c. Canonical genesis + peers + config**, exactly as §3: copy the published
`genesis.json` (sha256 must match), set `persistent_peers` to the existing
validators, `addr_book_strict=false`, `mempool.type="app"`,
`minimum-gas-prices="1000000000agmb"`, `evm-chain-id=821207`.

**d. Start as a FULL NODE and let it sync** (systemd unit per §5, `Restart=always`,
enabled). Wait until caught up before validating:
```bash
curl -s localhost:26667/status | jq .result.sync_info.catching_up   # must be false
```

**e. Fund the operator, then create the validator on-chain.** The operator account
needs ≥ self-bond + fees; fund it from the drip faucet or a transfer:
```bash
gembad tx bank send tnfaucet $(gembad keys show node3val -a --keyring-backend test --home "$H") \
  1100000000000000000000000agmb --from tnfaucet --gas auto --gas-adjustment 1.5 \
  --gas-prices 1000000000agmb --node tcp://localhost:26657 -y
cat > validator.json <<JSON
{ "pubkey": $(gembad comet show-validator --home "$H"),
  "amount": "1000000000000000000000000agmb", "moniker": "gemba-tn-val-node3",
  "commission-rate": "0.1", "commission-max-rate": "0.2",
  "commission-max-change-rate": "0.01", "min-self-delegation": "1" }
JSON
gembad tx staking create-validator validator.json --from node3val --keyring-backend test \
  --home "$H" --chain-id gemba-testnet-1 --node tcp://localhost:26667 \
  --gas auto --gas-adjustment 1.5 --gas-prices 1000000000agmb -y
```

**f. Verify it joined the active set and signs.** The new node enters the bonded set
at the end of the block the tx lands in:
```bash
gembad q staking validators --node tcp://localhost:26657 -o json | jq -r \
  '.validators[]|select(.status=="BOND_STATUS_BONDED")|.description.moniker'   # now N+1
# confirm it signs — check a SETTLED (older) block, not the in-flight one
# (a block commits at >2/3, so the latest commit may show one fewer signer):
gembad q slashing signing-info $(gembad comet show-validator --home "$H") \
  --node tcp://localhost:26657 -o json | jq .val_signing_info   # missed≈0, not jailed
```

## 8. BFT fault-tolerance test (≥4 validators)

With **4** validators, the set tolerates **one** offline (3/4 = 75% > 2/3), so the
chain keeps producing. Test it: `sudo systemctl stop gembad` on one node → confirm
the other three keep advancing → start it again → confirm it catches back up. (With
exactly 3, see the n=3 pause note in §6.)
