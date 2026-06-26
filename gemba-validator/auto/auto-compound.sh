#!/usr/bin/env bash
# GembaBlockchain validator auto-compound.
#
# Once per day: withdraw this validator's self-delegation rewards + commission, then
# delegate REINVEST_PCT (default 50%) of what was actually received back into its OWN
# self-delegation. The validator's stake compounds daily, so the founder validators keep
# getting stronger and anchor the bonded set.
#
# WHY (CLAUDE.md §16.8 / §16.9): the chain is free and GMB has no financial price, so
# casual validators who spin up a home node and turn it off tomorrow could collapse the
# bonded ratio (the security KPI; two such chains have died this way). The founder's
# validators auto-compound to keep ≥ ~66% bonded. NOTE: this is *consensus* power only —
# it earns the security budget; it grants NO governance/treasury power (§5.7, the Solidity
# Governor excludes the founder/reserves), so it does not re-centralise governance.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$DIR/validator-auto.env" ] && . "$DIR/validator-auto.env"
GEMBAD=${GEMBAD:-gembad}; HOME_DIR=${GEMBAD_HOME:-/root/.gembad}; KEY=${VAL_KEY:-valop}
KB=${KEYRING_BACKEND:-test}; CHAIN_ID=${CHAIN_ID:-gemba-testnet-1}; NODE=${NODE:-tcp://localhost:26657}
DENOM=${DENOM:-agmb}; PCT=${REINVEST_PCT:-50}; MIN_REINVEST=${MIN_REINVEST_AGMB:-1000000000000000000}
GAS_PRICES=${GAS_PRICES:-1000000000agmb}; LOG=${LOG_FILE:-/var/log/gemba-validator-auto.log}

COMMON="--home $HOME_DIR --keyring-backend $KB --chain-id $CHAIN_ID --node $NODE"
TX="--gas auto --gas-adjustment 1.5 --gas-prices $GAS_PRICES -y -o json"
log(){ echo "[$(date -Is)] compound: $*" >>"$LOG"; }

command -v jq >/dev/null || { log "jq missing"; exit 1; }
command -v bc >/dev/null || { log "bc missing"; exit 1; }

valoper=$($GEMBAD keys show "$KEY" --bech val -a $COMMON 2>/dev/null) || { log "cannot read valoper"; exit 1; }
deladdr=$($GEMBAD keys show "$KEY" -a $COMMON 2>/dev/null)
bal(){ $GEMBAD query bank balances "$deladdr" --node "$NODE" -o json 2>/dev/null \
       | jq -r --arg d "$DENOM" '(.balances[]|select(.denom==$d)|.amount) // "0"'; }

before=$(bal); before=${before:-0}
# withdraw self-delegation rewards AND commission in one tx
if ! $GEMBAD tx distribution withdraw-rewards "$valoper" --commission --from "$KEY" $COMMON $TX >/dev/null 2>&1; then
  log "withdraw-rewards submit failed (maybe nothing to withdraw) — continuing"
fi
sleep 8  # wait for inclusion
after=$(bal); after=${after:-0}

received=$(echo "$after - $before" | bc)
if [ "$(echo "$received <= 0" | bc)" = "1" ]; then log "no net rewards (before=$before after=$after) — skip"; exit 0; fi
reinvest=$(echo "$received * $PCT / 100" | bc)
if [ "$(echo "$reinvest < $MIN_REINVEST" | bc)" = "1" ]; then log "reinvest $reinvest < min $MIN_REINVEST — skip"; exit 0; fi

if $GEMBAD tx staking delegate "$valoper" "${reinvest}${DENOM}" --from "$KEY" $COMMON $TX >/dev/null 2>&1; then
  log "OK received=$received reinvest=$reinvest (${PCT}%) to $valoper"
else
  log "delegate FAILED for ${reinvest}${DENOM}"
  exit 1
fi
