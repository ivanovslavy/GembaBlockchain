#!/usr/bin/env bash
# =============================================================================
# ceremony-validator-box.sh — MAINNET key ceremony, VALIDATOR-box side.
# Run ON each of the 4 validator boxes. The operator key is BORN here and never
# leaves the box (only its ADDRESS and the gentx json travel back to the owner).
#
#   ./ceremony-validator-box.sh prepare   # init home + operator key (file keyring),
#                                         # print ADDRESS + node-id, encrypted backup
#   ./ceremony-validator-box.sh gentx     # after the pre-gentx genesis is distributed:
#                                         # self-bond 10,000 GMB, valgate-floor minimum
#
# Env: GEMBAD (default /usr/local/bin/gembad), HOME_DIR (default ~/.gembad),
#      MONIKER (default gemba-val-$(hostname -s))
# See docs/runbooks/mainnet-genesis-ceremony.md Phases 2-3.
# =============================================================================
set -euo pipefail
umask 077

EVMD="${GEMBAD:-/usr/local/bin/gembad}"
HOME_DIR="${HOME_DIR:-$HOME/.gembad}"
MONIKER="${MONIKER:-gemba-val-$(hostname -s 2>/dev/null || echo box)}"
CHAIN_ID="gemba-1"

die() { echo "FATAL: $*" >&2; exit 1; }
command -v gpg >/dev/null 2>&1 || die "gpg not installed"
[ -x "$EVMD" ] || die "gembad not found at \$GEMBAD=$EVMD (build it first — gemba-validator/install.sh builds from source)"

prepare() {
  if [ ! -f "$HOME_DIR/config/node_key.json" ]; then
    "$EVMD" init "$MONIKER" --chain-id "$CHAIN_ID" --home "$HOME_DIR" >/dev/null 2>&1
    echo ">> node home initialised at $HOME_DIR"
  else
    echo ">> node home exists at $HOME_DIR (keeping keys — init is never re-run)"
  fi
  if ! "$EVMD" keys show validator --keyring-backend file --home "$HOME_DIR" >/dev/null 2>&1; then
    echo ">> creating the OPERATOR key (file keyring — pick a strong passphrase; the"
    echo ">> printed mnemonic goes into the encrypted backup below, write it NOWHERE else)"
    "$EVMD" keys add validator --keyring-backend file --algo eth_secp256k1 --home "$HOME_DIR"
  fi
  ADDR="$("$EVMD" keys show validator -a --keyring-backend file --home "$HOME_DIR")"
  NODE_ID="$("$EVMD" comet show-node-id --home "$HOME_DIR")"
  IP="$(curl -4s --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"

  BK="$HOME/gemba-val-keys-$(hostname -s)-$(date +%Y%m%d).tar.gpg"
  tar -C "$HOME_DIR" -cf - config/priv_validator_key.json config/node_key.json keyring-file 2>/dev/null \
    | gpg --symmetric --cipher-algo AES256 --output "$BK"
  chmod 600 "$BK"; sha256sum "$BK"
  echo ""
  echo "================ REPORT BACK TO THE OWNER (public info only) ================"
  echo "  operator address : $ADDR"
  echo "  seed entry       : ${NODE_ID}@${IP}:26656"
  echo "============================================================================"
  echo ">> Encrypted key backup: $BK — move a copy OFF this box (it contains the"
  echo ">> validator identity: priv_validator_key + node_key + operator keyring)."
}

gentx() {
  [ -f "$HOME_DIR/config/genesis.json" ] || die "no genesis at $HOME_DIR/config/genesis.json — copy the distributed PRE-GENTX genesis first"
  grep -q '"chain_id": *"gemba-1"' "$HOME_DIR/config/genesis.json" || die "genesis at $HOME_DIR is not gemba-1"
  "$EVMD" genesis gentx validator 10000000000000000000000agmb \
    --min-self-delegation 1000000000000000000000 \
    --gas-prices 5000000000agmb \
    --keyring-backend file --chain-id "$CHAIN_ID" --home "$HOME_DIR"
  echo ">> gentx written to $HOME_DIR/config/gentx/ — send that json back to the owner."
}

case "${1:-}" in
  prepare) prepare ;;
  gentx) gentx ;;
  *) echo "usage: $0 {prepare|gentx}"; exit 1 ;;
esac
