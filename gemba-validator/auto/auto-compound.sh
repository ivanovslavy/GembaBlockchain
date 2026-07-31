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

# Single-instance lock (a manual run racing the timer); second instance exits quietly.
exec 9>/run/lock/gemba-auto-compound.lock 2>/dev/null || exec 9>/tmp/gemba-auto-compound.lock
flock -n 9 || exit 0

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

# GUARD: the configured CHAIN_ID must be the chain this node is actually on. A mismatch (e.g. a
# mainnet box left on the template's gemba-testnet-1) makes every tx we sign invalid, so the
# unjail/delegate would fail forever while the log still looked busy. Shout instead of pretending.
_net=$(curl -s --max-time 5 "${RPC_HTTP:-http://localhost:26657}/status" 2>/dev/null \
       | jq -r '.result.node_info.network // empty' 2>/dev/null || true)
if [ -n "$_net" ] && [ "$_net" != "$CHAIN_ID" ]; then
  log "CONFIG ERROR: CHAIN_ID=$CHAIN_ID but this node is on '$_net' — refusing to submit anything"
  notify "CONFIG ERROR: CHAIN_ID=$CHAIN_ID but the node is on $_net"
  exit 1
fi

valoper=$($GEMBAD keys show "$KEY" --bech val -a $KR 2>/dev/null) || { log "cannot read valoper"; exit 1; }
[ -z "$valoper" ] && { log "cannot read valoper (empty) — key $KEY missing?"; exit 1; }
deladdr=$($GEMBAD keys show "$KEY" -a $KR 2>/dev/null)
bal(){ $GEMBAD query bank balances "$deladdr" --node "$NODE" -o json 2>/dev/null \
       | jq -r --arg d "$DENOM" '(.balances[]|select(.denom==$d)|.amount) // "0"'; }
# Current self-delegation, in $DENOM. Plain state query — every node answers it, including
# validators running with `indexer = "null"` (tx indexing off). Returns 0 if no delegation yet.
selfdel(){ $GEMBAD query staking delegation "$deladdr" "$valoper" --node "$NODE" -o json 2>/dev/null \
       | jq -r '(.delegation_response.balance.amount // .balance.amount) // "0"' 2>/dev/null || echo 0; }

# --dry-run: compute and report what WOULD happen; submit nothing. For safe validation of a
# deploy without touching stake or spending a fee.
DRY_RUN=0; [ "${1:-}" = "--dry-run" ] && DRY_RUN=1

before=$(bal); before=${before:-0}
# withdraw self-delegation rewards AND commission in one tx
if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN: would withdraw rewards+commission for $valoper (balance now=$before, self-delegation=$(selfdel))"
else
  if ! $GEMBAD tx distribution withdraw-rewards "$valoper" --commission --from "$KEY" $COMMON $TX >/dev/null 2>&1; then
    log "withdraw-rewards submit failed (maybe nothing to withdraw) — continuing"
  fi
  sleep 8  # wait for inclusion
fi
after=$(bal); after=${after:-0}

received=$(echo "$after - $before" | bc)
if [ "$DRY_RUN" = "1" ]; then
  # We skipped the withdrawal, so nothing landed in the balance. Simulate what it WOULD be
  # from the pending rewards + commission. Both come back as decimal coin strings
  # ("123.456agmb"), so strip the denom and the fraction.
  _r=$($GEMBAD query distribution rewards "$deladdr" --node "$NODE" -o json 2>/dev/null \
       | jq -r --arg d "$DENOM" '[.total[]? | select(endswith($d))] | (.[0] // "0")' 2>/dev/null \
       | sed "s/${DENOM}$//" | cut -d. -f1)
  _c=$($GEMBAD query distribution commission "$valoper" --node "$NODE" -o json 2>/dev/null \
       | jq -r --arg d "$DENOM" '[.commission.commission[]? | select(endswith($d))] | (.[0] // "0")' 2>/dev/null \
       | sed "s/${DENOM}$//" | cut -d. -f1)
  received=$(echo "${_r:-0} + ${_c:-0}" | bc)
  log "DRY-RUN: pending rewards=${_r:-0} commission=${_c:-0} -> received(simulated)=$received"
fi
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
#
# VERIFICATION IS BY OUTCOME (self-delegation delta), not by tx hash. Reason: the validator
# boxes run with `indexer = "null"` in config.toml — tx indexing was deliberately switched
# OFF on 2026-07-15 as part of the disk-fill remediation (the index grows forever and pruning
# does not touch it; queries belong on the archive node per docs/runbooks/node-setup.md).
# So `q tx <hash>` is unavailable there and the old hash-based check silently degraded to
# "unverified" on every box except the home node. Reading the delegation back is a plain
# state query that EVERY node answers, needs no index, and proves the actual effect landed.
del_before=$(selfdel); del_before=${del_before:-0}

if [ "$DRY_RUN" = "1" ]; then
  log "DRY-RUN: would delegate ${reinvest}${DENOM} to $valoper | self-delegation now=$del_before | verify path OK"
  exit 0
fi

# Capture stdout (the JSON result) and stderr (gas-estimate noise) SEPARATELY — mixing them with
# 2>&1 made the JSON unparseable, so txhash came back empty.
_err=$(mktemp)
if ! out=$($GEMBAD tx staking delegate "$valoper" "${reinvest}${DENOM}" --from "$KEY" $COMMON $TX 2>"$_err"); then
  log "delegate submit error: $(tail -c 200 "$_err")"; rm -f "$_err"; exit 1
fi
rm -f "$_err"
submit_code=$(printf '%s' "$out" | jq -r '.code // 0' 2>/dev/null || echo 0)
txhash=$(printf '%s' "$out" | jq -r '.txhash // empty' 2>/dev/null || true)
if [ -z "$txhash" ]; then txhash=$(printf '%s' "$out" | grep -oiE '[0-9A-F]{64}' | head -1 || true); fi
if [ "$submit_code" != "0" ]; then
  log "delegate rejected at submit code=$submit_code raw=$(printf '%s' "$out" | jq -r '.raw_log // empty' 2>/dev/null | head -c 160)"; exit 1
fi
sleep 8  # wait for the block to commit

# --- PRIMARY: did the self-delegation actually grow? (works on every node) ---
del_after=$(selfdel); del_after=${del_after:-0}
grew=$(echo "$del_after - $del_before" | bc)

# --- SECONDARY: exact error code, only where tx indexing happens to be on (diagnostics) ---
exec_json=$($GEMBAD q tx "$txhash" --node "$NODE" -o json 2>/dev/null || echo '{}')
exec_code=$(printf '%s' "$exec_json" | jq -r '.code // empty' 2>/dev/null || echo "")
if [ -n "$exec_code" ] && [ "$exec_code" != "0" ]; then
  log "delegate EXECUTION FAILED code=$exec_code txhash=$txhash grew=$grew raw=$(printf '%s' "$exec_json" | jq -r '.raw_log // empty' 2>/dev/null | head -c 160)"; exit 1
fi

# Tolerance: 1% slack absorbs a slash landing between the two reads.
min_expected=$(echo "$reinvest * 99 / 100" | bc)
if [ "$(echo "$grew < $min_expected" | bc)" = "1" ]; then
  log "delegate NOT REFLECTED ON CHAIN — self-delegation grew by $grew, expected >= $min_expected (reinvest=$reinvest txhash=${txhash:-?}) — likely a §6 daily-cap revert"
  exit 1
fi
log "OK received=$received reinvest=$reinvest (${PCT}%) to $valoper | txhash=${txhash:-?} verified=delegation_delta grew=$grew before=$del_before after=$del_after${exec_code:+ exec_code=$exec_code}"
