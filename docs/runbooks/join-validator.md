# Join GembaBlockchain — one-command node / validator install

Permissionless (CLAUDE.md §3): anyone can run a node and, with stake, validate.
**One command** gets you a fully-synced node — it installs dependencies, builds the
binary from source (so it matches your machine's glibc — no portability traps),
pulls + verifies the official genesis, wires the seeds, and starts a systemd service.

## Install / update (one line)

```bash
curl -sSL https://raw.githubusercontent.com/ivanovslavy/GembaBlockchain/main/scripts/install-validator.sh | bash
```

Customise via env, e.g.:

```bash
MONIKER=my-validator curl -sSL .../scripts/install-validator.sh | bash
# or clone + run:  MONIKER=my-validator ./scripts/install-validator.sh
```

Re-running the same command **updates** the node (git pull + rebuild + restart). It
never overwrites your genesis or keys.

### Requirements
- Linux (Ubuntu/Debian or RHEL/Fedora), `sudo`, ~4 GB RAM, a few minutes for the first
  build, inbound **TCP 26656** (P2P) open.
- The script installs the rest itself (Go 1.25.9, git, jq, build tools).

## What it does (so there's no mystery)
1. installs OS deps + the pinned Go toolchain
2. fetches the source (`chain/` + the cosmos/evm wiring patch)
3. **builds `gembad` from source** → `/usr/local/bin/gembad`
4. `gembad init`, then downloads + **sha256-verifies** the official `genesis.json`
5. sets `seeds`, `minimum-gas-prices`, pruning
6. installs + starts the `gembad` systemd service
7. waits for RPC and prints sync status + the validator command

## Become a validator (after `catching_up=false`)
```bash
gembad keys add validator                      # or import your key
# fund it with GMB (drip faucet) above the min self-bond (1000 GMB, §5.2), then:
gembad tx staking create-validator \
  --amount 1000000000000000000000agmb \
  --pubkey "$(gembad comet show-validator)" \
  --moniker my-validator --commission-rate 0.10 \
  --commission-max-rate 0.20 --commission-max-change-rate 0.01 \
  --min-self-delegation 1 --chain-id gemba-testnet-1 \
  --from validator --gas auto --gas-adjustment 1.3 --gas-prices 1000000000agmb
```
Secure your consensus key (tmkms) and run a sentry: `docs/runbooks/validator-keys.md`,
`docs/runbooks/node-setup.md`.

## Network artifacts (public)
| Item | Value |
|---|---|
| chain-id | `gemba-testnet-1` (EVM chainId `821207`) |
| genesis | `https://testnet.gembascan.io/brand/genesis.json` (sha256 `2ee72507…bf3bf3c9`) |
| seeds | the 3 Contabo nodes `@13.140.139.82/83/84:26656` (in the script) |
| explorer | https://testnet.gembascan.io |

## ⚠️ Prerequisite for the public one-liner
The `curl | bash` form needs the **source to be reachable**:
- **Make the GitHub repo public** (CLAUDE.md §0.3 — it's intended to be), **or**
- during the private phase, pass a token: `GITHUB_TOKEN=<pat> ./install-validator.sh`.

Without one of these the clone step fails (a private repo cannot be `git clone`d
anonymously) — which is exactly the "permissionless on paper only" gap to close
before a public launch.
