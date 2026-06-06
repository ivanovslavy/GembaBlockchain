# GembaBlockchain — Validator Node

**Run a node and become a validator on GembaBlockchain — in two commands.**

```bash
git clone https://github.com/ivanovslavy/GembaBlockchain-Validator.git && cd GembaBlockchain-Validator
./install.sh
```

That's it. The installer sets up everything (dependencies, the Go toolchain, builds
the node, the genesis, peers, a systemd service) and leaves you with a **syncing
node**. When it's synced you fund a key and run one `create-validator` command.

---

## What is GembaBlockchain?

GembaBlockchain is a **public, decentralized, permissionless Proof‑of‑Stake L1** —
Bulgaria's first blockchain — built for public institutions and organizations to
deliver real services. Its native coin **Gemba (GMB)** is a **utility** coin
(cheaper service access, workplace access, tickets, perks) — value comes from *use*,
not speculation.

| | |
|---|---|
| Consensus | CometBFT BFT PoS — instant finality (~2 s), no reorgs |
| EVM | Full EVM (Solidity, MetaMask, Foundry, ethers/viem, JSON‑RPC) |
| Cosmos chain‑id | `gemba-testnet-1` |
| EVM chainId | `821207` |
| Native coin | **GMB** (staking + gas), base denom `agmb` (18 decimals) |
| Supply | fixed at genesis, **0% inflation** (validator rewards from a pre‑minted reserve) |
| Validator entry | **permissionless** — bond ≥ the min self‑bond, no KYC, no approval |

**Permissionless** means: anyone with enough GMB can validate. No operator approves
you. This repo is the public, self‑contained way to join.

> This is the **testnet** (`gemba-testnet-1`) — valueless tokens, for a real dress
> rehearsal. Get test GMB from the faucet; never reuse mainnet keys here.

---

## Requirements

- Linux (Ubuntu/Debian or RHEL/Fedora), `sudo`
- ~4 GB RAM and a few minutes for the first build
- Inbound **TCP 26656** open (P2P)
- The installer installs everything else (Go 1.25.9, git, jq, build tools)

> **Why build from source?** The binary is compiled **on your machine**, so it links
> against your system's libc — this eliminates the classic `GLIBC_x not found`
> portability problem. No prebuilt-binary version matrix to worry about.

---

## Step by step

### 1. Install (gets you a synced node)
```bash
git clone https://github.com/ivanovslavy/GembaBlockchain-Validator.git && cd GembaBlockchain-Validator
MONIKER=my-validator ./install.sh          # MONIKER is optional
```
The installer:
1. installs OS deps + the pinned Go toolchain
2. **builds `gembad` from the bundled node source** (`src/chain/`) → `/usr/local/bin/gembad`
3. `gembad init`, installs the **bundled, sha256‑verified** `genesis.json`
4. sets the public **seeds**, gas floor and pruning
5. installs + starts the **`gembad`** systemd service
6. prints sync status and the validator command

Watch it sync:
```bash
journalctl -u gembad -f
curl -s localhost:26657/status | jq .result.sync_info     # wait for catching_up=false
```

### 2. Get a key + test GMB
```bash
gembad keys add validator            # creates an operator key (back up the mnemonic!)
gembad keys show validator -a        # your cosmos1… address
```
Fund it from the **faucet** (link on the explorer) above the **1000 GMB** minimum
self‑bond (§5.2).

### 3. Become a validator (once `catching_up=false`)
```bash
gembad tx staking create-validator \
  --amount 1000000000000000000000agmb \
  --pubkey "$(gembad comet show-validator)" \
  --moniker "my-validator" \
  --commission-rate 0.10 --commission-max-rate 0.20 --commission-max-change-rate 0.01 \
  --min-self-delegation 1 \
  --chain-id gemba-testnet-1 --from validator \
  --gas auto --gas-adjustment 1.3 --gas-prices 1000000000agmb
```
Verify you're in the active set:
```bash
gembad q staking validator "$(gembad keys show validator --bech val -a)"
```

---

## Operate

| Action | Command |
|---|---|
| Logs | `journalctl -u gembad -f` |
| Restart | `sudo systemctl restart gembad` |
| Stop | `sudo systemctl stop gembad` |
| **Update** (pull + rebuild + restart) | `git pull && ./install.sh` |
| Sync status | `curl -s localhost:26657/status \| jq .result.sync_info` |
| Node id | `gembad comet show-node-id` |

### Security (do this for a real validator)
- **Protect your consensus key** — use a remote signer (`tmkms`) and a **sentry**
  architecture so your validator's IP isn't exposed. See the project's
  `docs/runbooks/validator-keys.md` and `node-setup.md`.
- Back up `~/.gembad/config/priv_validator_key.json` and your operator mnemonic
  **offline**. Losing the consensus key (and double‑signing with a restored copy)
  gets you slashed/tombstoned.

---

## Network parameters

| | |
|---|---|
| chain‑id / EVM chainId | `gemba-testnet-1` / `821207` |
| genesis | bundled `genesis.json` (sha256 `2ee72507…bf3bf3c9`, verified by the installer) |
| seeds | `13.140.139.82 / .83 / .84 : 26656` (in `network.env`) |
| min self‑bond | 1000 GMB (§5.2) |
| explorer | https://testnet.gembascan.io |

All of these live in **`network.env`** — the single config the installer reads.

---

## Troubleshooting
- **build OOM:** give the box ≥ 4 GB RAM (or add swap) and re‑run.
- **stuck `catching_up=true`:** check TCP 26656 is open and the seeds are reachable
  (`gembad comet show-node-id`; logs for peer dials).
- **not entering the active set:** you must bond ≥ the min self‑bond and out‑rank the
  set cap; being out‑ranked isn't a kick — bond more (§5.2).

---

## License
Apache‑2.0 (matches the GembaBlockchain / Cosmos EVM stack). See `LICENSE`.
