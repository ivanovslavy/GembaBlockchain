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
# Load config: the installed location (systemd EnvironmentFile) first, then a repo-local copy.
for _f in /etc/gemba/validator-auto.env "$DIR/validator-auto.env"; do [ -f "$_f" ] && . "$_f" && break; done
GEMBAD=${GEMBAD:-gembad}; HOME_DIR=${GEMBAD_HOME:-/root/.gembad}; KEY=${VAL_KEY:-valop}
KB=${KEYRING_BACKEND:-test}; CHAIN_ID=${CHAIN_ID:-gemba-testnet-1}; NODE=${NODE:-tcp://localhost:26657}
DENOM=${DENOM:-agmb}; PCT=${REINVEST_PCT:-50}; MIN_REINVEST=${MIN_REINVEST_AGMB:-1000000000000000000}
GAS_PRICES=${GAS_PRICES:-1000000000agmb}; LOG=${LOG_FILE:-/var/log/gemba-validator-auto.log}

COMMON="--home $HOME_DIR --keyring-backend $KB --chain-id $CHAIN_ID --node $NODE"
KR="--home $HOME_DIR --keyring-backend $KB"   # `keys show` rejects --chain-id/--node
TX="--gas auto --gas-adjustment 1.5 --gas-prices $GAS_PRICES -y -o json"
log(){ echo "[$(date -Is)] compound: $*" >>"$LOG"; }

command -v jq >/dev/null || { log "jq missing"; exit 1; }
command -v bc >/dev/null || { log "bc missing"; exit 1; }

valoper=$($GEMBAD keys show "$KEY" --bech val -a $KR 2>/dev/null) || { log "cannot read valoper"; exit 1; }
[ -z "$valoper" ] && { log "cannot read valoper (empty) — key $KEY missing?"; exit 1; }
deladdr=$($GEMBAD keys show "$KEY" -a $KR 2>/dev/null)
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
# Clamp to the §6 daily bond-increase cap so the on-chain ante NEVER rejects us — if we'd exceed
# the cap, delegate the MAX allowed and leave the rest liquid (no error, no panic).
MAX_DAILY_ADD=${MAX_DAILY_ADD_AGMB:-50000000000000000000}  # 50 GMB default (= valgate cap)
if [ "$(echo "$reinvest > $MAX_DAILY_ADD" | bc)" = "1" ]; then
  log "reinvest $reinvest capped to daily max $MAX_DAILY_ADD (§6)"; reinvest=$MAX_DAILY_ADD
fi
if [ "$(echo "$reinvest < $MIN_REINVEST" | bc)" = "1" ]; then log "reinvest $reinvest < min $MIN_REINVEST — skip"; exit 0; fi

# Submit the delegate, then VERIFY it actually executed on-chain — not just that it was
# submitted. A delegate can pass CheckTx (get a hash) but REVERT in the block (e.g. the §6
# 50-GMB/day bond-increase cap), and the bare CLI exit would mislead us into logging "OK".
if ! out=$($GEMBAD tx staking delegate "$valoper" "${reinvest}${DENOM}" --from "$KEY" $COMMON $TX 2>&1); then
  log "delegate submit error: $(printf '%s' "$out" | tail -c 200)"; exit 1
fi
submit_code=$(printf '%s' "$out" | jq -r '.code // 0' 2>/dev/null || echo 0)
txhash=$(printf '%s' "$out" | jq -r '.txhash // empty' 2>/dev/null || echo "")
if [ "$submit_code" != "0" ]; then
  log "delegate rejected at submit code=$submit_code raw=$(printf '%s' "$out" | jq -r '.raw_log // empty' 2>/dev/null | head -c 160)"; exit 1
fi
sleep 8  # wait for the tx to be indexed, then read its EXECUTION result code
exec_json=$($GEMBAD q tx "$txhash" --node "$NODE" -o json 2>/dev/null || echo '{}')
exec_code=$(printf '%s' "$exec_json" | jq -r '.code // empty' 2>/dev/null || echo "")
if [ -n "$exec_code" ] && [ "$exec_code" != "0" ]; then
  log "delegate EXECUTION FAILED code=$exec_code txhash=$txhash raw=$(printf '%s' "$exec_json" | jq -r '.raw_log // empty' 2>/dev/null | head -c 160)"; exit 1
fi
# fail-safe: if the result couldn't be fetched, don't block — the clamp makes a cap-rejection unlikely
log "OK received=$received reinvest=$reinvest (${PCT}%) to $valoper | confirmed txhash=${txhash:-?} exec_code=${exec_code:-unverified}"
