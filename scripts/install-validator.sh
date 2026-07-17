#!/usr/bin/env bash
# =============================================================================
# install-validator.sh — ONE-COMMAND GembaBlockchain node/validator installer.
#
# Goal (CLAUDE.md §3, permissionless): anyone can stand up a fully-synced node
# with a single command — no 100 manual steps. This script fetches sources,
# updates, installs dependencies, BUILDS the binary from source (which also makes
# the glibc-portability problem disappear — the binary links against THIS machine's
# libc), initialises the node, pulls + verifies the official genesis, wires the
# seeds, installs a systemd service, and starts it. Re-running it = update.
#
#   curl -sSL https://raw.githubusercontent.com/ivanovslavy/GembaBlockchain/main/scripts/install-validator.sh | bash
#   # or:  MONIKER=my-node ./install-validator.sh
#
# After it finishes you have a syncing full node. To BECOME a validator you then
# fund your operator key and run the printed `gembad tx staking create-validator`.
#
# Idempotent: safe to re-run to update (git pull + rebuild + restart). It will NOT
# overwrite an existing genesis or your keys.
#
# Requirements: Linux (Ubuntu/Debian apt, or RHEL/Fedora dnf), sudo, ~4 GB RAM and
# a few minutes for the first build, ports 26656 (P2P, inbound) open.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Network selection — EXPLICIT, never implied (owner 2026-07-17): a node silently
# joining the wrong network is worse than one extra word in the command.
#   GEMBA_NETWORK=testnet ./install-validator.sh     (gemba-testnet-1 / 821207)
#   GEMBA_NETWORK=mainnet ./install-validator.sh     (gemba-1 / 821206)
# Every network default below keys off this; each is still env-overridable.
# ---------------------------------------------------------------------------
GEMBA_NETWORK="${GEMBA_NETWORK:-}"
case "$GEMBA_NETWORK" in
  testnet)
    NETWORK_DEF="gemba-testnet-1"; CHAIN_ID_DEF="gemba-testnet-1"; EVM_CHAIN_ID_DEF="821207"
    GENESIS_URL_DEF="https://testnet.gembascan.io/brand/genesis.json"
    GENESIS_SHA256_DEF="2ee72507b420443b23e0667f976d2d86c6b8bf7c88a8112e1145c2c8bf3bf3c9"
    SEEDS_DEF="44935754a7ea7e5ced5528eb39b5b4f6de73d3bb@13.140.139.82:26656,5473057935d09332c6051e7e83902ae226e060d2@13.140.139.83:26656,b7588b7dcd3e90bc0306dce68f7c95c5306d74a6@13.140.139.84:26656"
    MIN_GAS_PRICES_DEF="1000000000agmb"
    ;;
  mainnet)
    NETWORK_DEF="gemba-1"; CHAIN_ID_DEF="gemba-1"; EVM_CHAIN_ID_DEF="821206"
    GENESIS_URL_DEF="https://gembascan.io/brand/genesis.json"
    GENESIS_SHA256_DEF=""   # published at the genesis ceremony — REQUIRED until then
    SEEDS_DEF=""            # published at the genesis ceremony — REQUIRED until then
    MIN_GAS_PRICES_DEF="5000000000agmb"   # mainnet fee floor is 5 gwei (ADR-008a)
    ;;
  *)
    echo "FATAL: set GEMBA_NETWORK=testnet or GEMBA_NETWORK=mainnet explicitly." >&2
    echo "  e.g.  GEMBA_NETWORK=testnet MONIKER=my-node $0" >&2
    exit 1
    ;;
esac
NETWORK="${NETWORK:-$NETWORK_DEF}"
CHAIN_ID="${CHAIN_ID:-$CHAIN_ID_DEF}"
EVM_CHAIN_ID="${EVM_CHAIN_ID:-$EVM_CHAIN_ID_DEF}"
MONIKER="${MONIKER:-gemba-node-$(hostname -s 2>/dev/null || echo node)}"

# Source + build (build-from-source = glibc-portable, reproducible)
GEMBA_REPO="${GEMBA_REPO:-https://github.com/ivanovslavy/GembaBlockchain.git}"
REPO_REF="${REPO_REF:-main}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"           # only needed while the repo is private
GO_VERSION="${GO_VERSION:-1.25.9}"         # must satisfy chain/go.mod

# Official network artifacts (must be publicly hosted)
GENESIS_URL="${GENESIS_URL:-$GENESIS_URL_DEF}"
GENESIS_SHA256="${GENESIS_SHA256:-$GENESIS_SHA256_DEF}"
SEEDS="${SEEDS:-$SEEDS_DEF}"
PERSISTENT_PEERS="${PERSISTENT_PEERS:-}"
# Mainnet refuses to run on blanks — no genesis hash / seeds means the ceremony
# artifacts aren't published yet; guessing would be dangerous.
if [ "$GEMBA_NETWORK" = "mainnet" ]; then
  [ -n "$GENESIS_SHA256" ] || { echo "FATAL: GENESIS_SHA256 is required for mainnet (published at the genesis ceremony — see gemba-validator/network.mainnet.env)" >&2; exit 1; }
  [ -n "$SEEDS" ] || { echo "FATAL: SEEDS is required for mainnet (published at the genesis ceremony)" >&2; exit 1; }
fi

# Node config
HOME_DIR="${HOME_DIR:-$HOME/.gembad}"
MIN_GAS_PRICES="${MIN_GAS_PRICES:-$MIN_GAS_PRICES_DEF}"   # node mempool anti-spam floor
PRUNING="${PRUNING:-custom}"                          # validators prune (node-setup.md)
ENABLE_JSONRPC="${ENABLE_JSONRPC:-false}"             # true only for RPC providers/explorer
SVC_USER="${SVC_USER:-$USER}"
BIN=/usr/local/bin/gembad
WORK="${WORK:-$HOME/.gemba-build}"

log()  { printf '\033[1;32m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# ---------------------------------------------------------------------------
step_deps() {
  log "installing OS dependencies"
  if   command -v apt-get >/dev/null; then
    $SUDO apt-get update -qq
    $SUDO apt-get install -y -qq git curl jq build-essential ca-certificates >/dev/null
  elif command -v dnf >/dev/null; then
    $SUDO dnf install -y -q git curl jq gcc gcc-c++ make ca-certificates >/dev/null
  else
    warn "unknown package manager — ensure git, curl, jq, gcc/make are installed"
  fi
}

step_go() {
  local have=""; command -v go >/dev/null && have="$(go version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  # install required Go if missing or older than requested
  if [ -z "$have" ] || [ "$(printf '%s\n%s' "$GO_VERSION" "$have" | sort -V | head -1)" != "$GO_VERSION" ]; then
    local arch; case "$(uname -m)" in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; *) die "unsupported arch $(uname -m)";; esac
    log "installing Go $GO_VERSION ($arch)"
    curl -sSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" -o /tmp/go.tgz
    $SUDO rm -rf /usr/local/go && $SUDO tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
    $SUDO ln -sf /usr/local/go/bin/go /usr/local/bin/go
    $SUDO ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  else
    log "Go $have present (>= $GO_VERSION) ✓"
  fi
  export PATH="/usr/local/go/bin:$PATH"
}

step_source() {
  local url="$GEMBA_REPO"
  [ -n "$GITHUB_TOKEN" ] && url="https://x-access-token:${GITHUB_TOKEN}@${GEMBA_REPO#https://}"
  if [ -d "$WORK/.git" ]; then
    log "updating source ($REPO_REF)"; git -C "$WORK" remote set-url origin "$url"
    git -C "$WORK" fetch -q --depth 1 origin "$REPO_REF" && git -C "$WORK" reset -q --hard FETCH_HEAD
  else
    log "cloning source from ${GEMBA_REPO} ($REPO_REF)"
    git clone -q --depth 1 --branch "$REPO_REF" "$url" "$WORK" \
      || die "clone failed — if the repo is private, pass GITHUB_TOKEN=<pat>"
  fi
}

step_build() {
  log "building gembad from source (cosmos/evm + Gemba modules) — this can take a few minutes"
  OUT=/tmp/gembad.new bash "$WORK/chain/gembad/build-gembad.sh"
  $SUDO install -m 0755 /tmp/gembad.new "$BIN" && rm -f /tmp/gembad.new
  log "installed: $($BIN version 2>/dev/null || echo "$BIN")"
}

step_init() {
  if [ -f "$HOME_DIR/config/genesis.json" ]; then
    log "node already initialised at $HOME_DIR (keeping genesis & keys)"; return
  fi
  log "initialising node ($MONIKER, $CHAIN_ID)"
  "$BIN" init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR" >/dev/null 2>&1
}

step_genesis() {
  [ -s "$HOME_DIR/config/genesis.json" ] && [ "$(jq -r '.chain_id' "$HOME_DIR/config/genesis.json" 2>/dev/null)" = "$CHAIN_ID" ] && { log "genesis present ✓"; return; }
  log "fetching official genesis from $GENESIS_URL"
  curl -sSL "$GENESIS_URL" -o "$HOME_DIR/config/genesis.json" || die "genesis download failed ($GENESIS_URL)"
  if [ -n "$GENESIS_SHA256" ]; then
    local got; got="$(sha256sum "$HOME_DIR/config/genesis.json" | awk '{print $1}')"
    [ "$got" = "$GENESIS_SHA256" ] || die "genesis sha256 MISMATCH (got $got, want $GENESIS_SHA256)"
    log "genesis sha256 verified ✓"
  else
    warn "GENESIS_SHA256 not set — skipping integrity check (set it for production)"
  fi
}

step_config() {
  log "configuring peers / gas / pruning"
  local C="$HOME_DIR/config/config.toml" A="$HOME_DIR/config/app.toml"
  sed -i "s|^seeds = .*|seeds = \"$SEEDS\"|" "$C"
  [ -n "$PERSISTENT_PEERS" ] && sed -i "s|^persistent_peers = .*|persistent_peers = \"$PERSISTENT_PEERS\"|" "$C"
  sed -i "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICES\"|" "$A"
  sed -i "s|^pruning = .*|pruning = \"$PRUNING\"|" "$A"
  if [ "$ENABLE_JSONRPC" = "true" ]; then
    sed -i "s|^enable = .*|enable = true|" "$A" 2>/dev/null || true   # [json-rpc] enable
  fi
}

step_service() {
  log "installing systemd service (gembad)"
  local START="$BIN start --home $HOME_DIR --chain-id $CHAIN_ID --evm.evm-chain-id $EVM_CHAIN_ID --minimum-gas-prices $MIN_GAS_PRICES"
  [ "$ENABLE_JSONRPC" = "true" ] && START="$START --json-rpc.enable=true --json-rpc.address 0.0.0.0:8545 --json-rpc.ws-address 0.0.0.0:8546 --json-rpc.api eth,net,web3,txpool,debug"
  $SUDO tee /etc/systemd/system/gembad.service >/dev/null <<EOF
[Unit]
Description=GembaBlockchain node ($NETWORK)
After=network-online.target
Wants=network-online.target

[Service]
User=$SVC_USER
Type=simple
ExecStart=$START
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now gembad
}

step_status() {
  log "node started. waiting for RPC…"
  local i h cu
  for i in $(seq 1 24); do
    if h=$(curl -s localhost:26657/status 2>/dev/null | jq -r '.result.sync_info.latest_block_height' 2>/dev/null) && [ -n "$h" ] && [ "$h" != "null" ]; then
      cu=$(curl -s localhost:26657/status | jq -r '.result.sync_info.catching_up')
      log "height=$h  catching_up=$cu"; break
    fi; sleep 5
  done
  cat <<EOF

============================================================================
 ✅ GembaBlockchain node is installed and running ($NETWORK).
   binary : $BIN  ($($BIN version 2>/dev/null))
   home   : $HOME_DIR
   logs   : journalctl -u gembad -f
   status : curl -s localhost:26657/status | jq .result.sync_info
   update : re-run this script (git pull + rebuild + restart)

 Wait until  catching_up=false  (fully synced), then BECOME A VALIDATOR:
   1) create/import an operator key:   gembad keys add validator
   2) fund it with GMB (drip faucet) above the min self-bond (1000 GMB §5.2)
   3) gembad tx staking create-validator \\
        --amount 1000000000000000000000agmb \\
        --pubkey "\$(gembad comet show-validator --home $HOME_DIR)" \\
        --moniker "$MONIKER" --commission-rate 0.10 \\
        --commission-max-rate 0.20 --commission-max-change-rate 0.01 \\
        --min-self-delegation 1000000000000000000000 --chain-id $CHAIN_ID \\
        --from validator --gas auto --gas-adjustment 1.3 --gas-prices $MIN_GAS_PRICES
   (min-self-delegation must be >= the x/valgate floor of 1000 GMB = 1000e18 agmb —
    the chain REJECTS create-validator below it, §5.2)
   For key security (tmkms) + sentry setup see docs/runbooks/validator-keys.md
============================================================================
EOF
}

main() {
  log "GembaBlockchain installer — network=$NETWORK chain-id=$CHAIN_ID moniker=$MONIKER"
  step_deps; step_go; step_source; step_build; step_init; step_genesis; step_config; step_service; step_status
}
main "$@"
