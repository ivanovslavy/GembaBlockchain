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
# Load config: the installed location (systemd EnvironmentFile) first, then a repo-local copy.
for _f in /etc/gemba/validator-auto.env "$DIR/validator-auto.env"; do [ -f "$_f" ] && . "$_f" && break; done
GEMBAD=${GEMBAD:-gembad}; HOME_DIR=${GEMBAD_HOME:-/root/.gembad}; KEY=${VAL_KEY:-valop}
KB=${KEYRING_BACKEND:-test}; CHAIN_ID=${CHAIN_ID:-gemba-testnet-1}; NODE=${NODE:-tcp://localhost:26657}
RPC=${RPC_HTTP:-http://localhost:26657}; GAS_PRICES=${GAS_PRICES:-1000000000agmb}
LOG=${LOG_FILE:-/var/log/gemba-validator-auto.log}

COMMON="--home $HOME_DIR --keyring-backend $KB --chain-id $CHAIN_ID --node $NODE"
KR="--home $HOME_DIR --keyring-backend $KB"   # `keys show` rejects --chain-id/--node
TX="--gas auto --gas-adjustment 1.5 --gas-prices $GAS_PRICES -y -o json"
log(){ echo "[$(date -Is)] unjail: $*" >>"$LOG"; }

command -v jq >/dev/null || { log "jq missing"; exit 1; }
valoper=$($GEMBAD keys show "$KEY" --bech val -a $KR 2>/dev/null) || { log "cannot read valoper"; exit 1; }
[ -z "$valoper" ] && { log "cannot read valoper (empty) — key $KEY missing?"; exit 1; }

jailed=$($GEMBAD query staking validator "$valoper" --node "$NODE" -o json 2>/dev/null \
         | jq -r '(.validator.jailed // .jailed) // "unknown"')
[ "$jailed" = "true" ] || exit 0  # not jailed → nothing to do

# Query catching-up through $GEMBAD (host `gembad` OR `docker exec <ctr> gembad`), NOT a host-side
# curl: when the node's RPC is only reachable inside a container, `curl localhost:26657` fails.
# Also read the boolean DIRECTLY — jq's `//` treats boolean false as empty, so the old
# `.catching_up // "true"` wrongly yielded "true" even when caught up, so it never unjailed.
# Only a literal "false" (caught up) proceeds; anything else (catching up / unreachable) stays
# "true" so we never unjail a node that cannot sign.
catching=$($GEMBAD status 2>/dev/null | jq -r '(.sync_info // .SyncInfo).catching_up' 2>/dev/null)
[ "$catching" = "false" ] || catching="true"
if [ "$catching" = "true" ]; then log "jailed but still catching up — NOT unjailing yet"; exit 0; fi

if $GEMBAD tx slashing unjail --from "$KEY" $COMMON $TX >/dev/null 2>&1; then
  log "unjail submitted (node caught up)"
else
  log "unjail not possible yet (inside jail window, or tombstoned) — will retry"
fi
