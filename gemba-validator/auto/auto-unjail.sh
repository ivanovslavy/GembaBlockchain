#!/usr/bin/env bash
# GembaBlockchain validator auto-unjail.
#
# Runs every few minutes. If THIS validator is jailed (e.g. a downtime blip) AND the node
# has caught up, it submits MsgUnjail. The unjail tx fails harmlessly while the node is
# still inside the downtime jail window, so the timer simply retries until it succeeds —
# the validator comes back without a human at 3am.
#
# SAFETY: it will NOT unjail while the node is still catching up — unjailing a node that
# cannot sign would just get it re-jailed (and slashed again). Downtime slashing is minor
# and the forfeited stake goes to the faucet, not burned (x/slashfunds, §5.6). Double-sign
# tombstones are permanent and CANNOT be unjailed — this script never tries (the validator
# query will show it tombstoned and unjail reverts; we log and move on).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/validator-auto.env" ] && . "$DIR/validator-auto.env"
GEMBAD=${GEMBAD:-gembad}; HOME_DIR=${GEMBAD_HOME:-/root/.gembad}; KEY=${VAL_KEY:-valop}
KB=${KEYRING_BACKEND:-test}; CHAIN_ID=${CHAIN_ID:-gemba-testnet-1}; NODE=${NODE:-tcp://localhost:26657}
RPC=${RPC_HTTP:-http://localhost:26657}; GAS_PRICES=${GAS_PRICES:-1000000000agmb}
LOG=${LOG_FILE:-/var/log/gemba-validator-auto.log}

COMMON="--home $HOME_DIR --keyring-backend $KB --chain-id $CHAIN_ID --node $NODE"
TX="--gas auto --gas-adjustment 1.5 --gas-prices $GAS_PRICES -y -o json"
log(){ echo "[$(date -Is)] unjail: $*" >>"$LOG"; }

command -v jq >/dev/null || { log "jq missing"; exit 1; }
valoper=$($GEMBAD keys show "$KEY" --bech val -a $COMMON 2>/dev/null) || { log "cannot read valoper"; exit 1; }

jailed=$($GEMBAD query staking validator "$valoper" --node "$NODE" -o json 2>/dev/null \
         | jq -r '(.validator.jailed // .jailed) // "unknown"')
[ "$jailed" = "true" ] || exit 0  # not jailed → nothing to do

catching=$(curl -s --max-time 5 "$RPC/status" | jq -r '.result.sync_info.catching_up // "true"')
if [ "$catching" = "true" ]; then log "jailed but still catching up — NOT unjailing yet"; exit 0; fi

if $GEMBAD tx slashing unjail --from "$KEY" $COMMON $TX >/dev/null 2>&1; then
  log "unjail submitted (node caught up)"
else
  log "unjail not possible yet (inside jail window, or tombstoned) — will retry"
fi
