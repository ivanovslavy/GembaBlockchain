#!/usr/bin/env bash
# =============================================================================
# install.sh — GembaBlockchain validator/node installer (self-contained).
#
# Two commands and you have a synced node:
#     git clone https://github.com/ivanovslavy/GembaBlockchain-Validator.git && cd GembaBlockchain-Validator
#     ./install.sh
#
# It installs dependencies + the pinned Go, BUILDS `gembad` from source (so the
# binary matches THIS machine's glibc — no portability traps), installs the
# bundled + sha256-verified genesis, wires the public seeds, installs a systemd
# service and starts it. Re-run to update (git pull + rebuild + restart). It never
# overwrites your keys or an existing genesis.
#
# Override anything via env, e.g.  MONIKER=my-validator ./install.sh
# Requirements: Linux (apt or dnf), sudo, ~4 GB RAM, a few minutes, inbound TCP 26656.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/network.env"

MONIKER="${MONIKER:-gemba-node-$(hostname -s 2>/dev/null || echo node)}"
HOME_DIR="${HOME_DIR:-$HOME/.gembad}"
ENABLE_JSONRPC="${ENABLE_JSONRPC:-false}" # true only for RPC providers / explorers
SVC_USER="${SVC_USER:-$USER}"
SRC="$HERE/src/chain"                      # bundled node source (self-contained)
BIN=/usr/local/bin/gembad

log()  { printf '\033[1;32m>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

deps() {
  log "installing OS dependencies"
  if   command -v apt-get >/dev/null; then $SUDO apt-get update -qq && $SUDO apt-get install -y -qq git curl jq build-essential ca-certificates >/dev/null
  elif command -v dnf     >/dev/null; then $SUDO dnf install -y -q git curl jq gcc gcc-c++ make ca-certificates >/dev/null
  else warn "unknown package manager — ensure git, curl, jq, gcc/make are installed"; fi
}

go_toolchain() {
  local have=""; command -v go >/dev/null && have="$(go version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
  if [ -z "$have" ] || [ "$(printf '%s\n%s' "$GO_VERSION" "$have" | sort -V | head -1)" != "$GO_VERSION" ]; then
    local arch; case "$(uname -m)" in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; *) die "unsupported arch $(uname -m)";; esac
    log "installing Go $GO_VERSION ($arch)"
    curl -sSL "https://go.dev/dl/go${GO_VERSION}.linux-${arch}.tar.gz" -o /tmp/go.tgz
    $SUDO rm -rf /usr/local/go && $SUDO tar -C /usr/local -xzf /tmp/go.tgz && rm -f /tmp/go.tgz
    $SUDO ln -sf /usr/local/go/bin/go /usr/local/bin/go; $SUDO ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  else log "Go $have present ✓"; fi
  export PATH="/usr/local/go/bin:$PATH"
}

build() {
  log "building gembad from the BUNDLED node source (a few minutes the first time)…"
  [ -x "$SRC/gembad/build-gembad.sh" ] || die "bundled source missing at $SRC — is the package complete?"
  # build-gembad.sh fetches the pinned, PUBLIC cosmos/evm and wires in $SRC (the Gemba modules)
  OUT=/tmp/gembad.new bash "$SRC/gembad/build-gembad.sh"
  $SUDO install -m 0755 /tmp/gembad.new "$BIN" && rm -f /tmp/gembad.new
  log "installed $($BIN version 2>/dev/null || echo gembad)"
}

init_node() {
  [ -f "$HOME_DIR/config/genesis.json" ] && { log "node already initialised (keeping genesis & keys)"; return; }
  log "initialising node ($MONIKER, $CHAIN_ID)"
  "$BIN" init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR" >/dev/null 2>&1
}

genesis() {
  if [ -s "$HOME_DIR/config/genesis.json" ] && [ "$(jq -r .chain_id "$HOME_DIR/config/genesis.json" 2>/dev/null)" = "$CHAIN_ID" ]; then log "genesis present ✓"; return; fi
  log "installing bundled genesis + verifying sha256"
  local got; got="$(sha256sum "$HERE/genesis.json" | awk '{print $1}')"
  [ "$got" = "$GENESIS_SHA256" ] || die "bundled genesis sha256 MISMATCH (got $got want $GENESIS_SHA256)"
  cp "$HERE/genesis.json" "$HOME_DIR/config/genesis.json"; log "genesis verified ✓"
}

configure() {
  log "configuring seeds / gas / pruning"
  local C="$HOME_DIR/config/config.toml" A="$HOME_DIR/config/app.toml"
  sed -i "s|^seeds = .*|seeds = \"$SEEDS\"|" "$C"
  sed -i "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICES\"|" "$A"
  sed -i "s|^pruning = .*|pruning = \"$PRUNING\"|" "$A"
}

service() {
  log "installing + starting systemd service"
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
  $SUDO systemctl daemon-reload && $SUDO systemctl enable --now gembad
}

status() {
  local i h cu
  for i in $(seq 1 24); do
    h=$(curl -s localhost:26657/status 2>/dev/null | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || true)
    [ -n "${h:-}" ] && [ "$h" != "null" ] && { cu=$(curl -s localhost:26657/status | jq -r '.result.sync_info.catching_up'); log "height=$h catching_up=$cu"; break; }
    sleep 5
  done
  cat <<EOF

============================================================================
 ✅ GembaBlockchain node running ($NETWORK)   binary: $($BIN version 2>/dev/null)
    logs:   journalctl -u gembad -f
    status: curl -s localhost:26657/status | jq .result.sync_info
    update: re-run ./install.sh

 When catching_up=false (fully synced), BECOME A VALIDATOR:
   gembad keys add validator                 # or import an existing key
   # fund it with GMB from the faucet above the $MIN_SELF_BOND_GMB GMB min self-bond, then:
   gembad tx staking create-validator \\
     --amount ${MIN_SELF_BOND_GMB}000000000000000000agmb \\
     --pubkey "\$(gembad comet show-validator)" \\
     --moniker "$MONIKER" --commission-rate 0.10 --commission-max-rate 0.20 \\
     --commission-max-change-rate 0.01 --min-self-delegation 1 \\
     --chain-id $CHAIN_ID --from validator \\
     --gas auto --gas-adjustment 1.3 --gas-prices $MIN_GAS_PRICES
============================================================================
EOF
}

log "GembaBlockchain validator installer — $NETWORK (moniker=$MONIKER)"
deps; go_toolchain; build; init_node; genesis; configure; service; status
