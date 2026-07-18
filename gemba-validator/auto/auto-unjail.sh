#!/usr/bin/env bash
# GembaBlockchain validator WATCHDOG — three layers: detect-stuck -> restart -> (sync) -> unjail.
#
# Runs every few minutes (systemd timer). Brings a validator back to signing WITHOUT a human,
# and — crucially — fixes the class of failure the old unjail-only script could not:
#
#   Old bug: it asked the LOCAL node "am I jailed?". A node that lost its peers and FROZE is
#   stuck in the past — at its frozen height it is not yet jailed, so it answered "no" and the
#   script did nothing, forever. The real problem (lost connectivity) was never addressed.
#
# The fix is a pipeline, not a single check:
#   LAYER 1 (DETECT + RESTART): decide "is this node actually stuck?" from signals that a frozen
#           node CANNOT fake — peer count == 0, or height not advancing between runs, or (if a
#           public tip is configured) far behind the network. If stuck, restart the node service
#           so it re-dials peers and catches up. Backoff + a hard cap prevent restart storms.
#   LAYER 2 (SYNC GATE): only proceed past here once the node is genuinely caught up (peers > 0,
#           not catching up, and within margin of the network tip). Never unjail a node that
#           cannot sign — it would just be re-jailed and slashed again.
#   LAYER 3 (UNJAIL): now that the node is synced, its own jail status is authoritative (the old
#           bug is impossible here — we only read it AFTER confirming sync). If jailed, submit
#           MsgUnjail. It reverts harmlessly while still inside the downtime window or if the
#           validator is tombstoned (permanent double-sign jail) — the timer just retries.
#
# External truth for "the network tip": the raw CometBFT RPC (26657) is intentionally NOT public
# (hardening — smaller attack surface), so we read the tip from the PUBLIC EVM JSON-RPC
# (eth_blockNumber) instead. Configure TIP_EVM_RPCS with any public endpoint(s); leave empty to
# fall back to the two purely-local stuck signals (peers==0 / height-not-advancing), which already
# catch the real-world failure mode. jail status is ALWAYS read locally, but only once synced.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load config: the installed location (systemd EnvironmentFile) first, then a repo-local copy.
for _f in /etc/gemba/validator-auto.env "$DIR/validator-auto.env"; do [ -f "$_f" ] && . "$_f" && break; done
GEMBAD=${GEMBAD:-gembad}; HOME_DIR=${GEMBAD_HOME:-/root/.gembad}; KEY=${VAL_KEY:-valop}
KB=${KEYRING_BACKEND:-test}; CHAIN_ID=${CHAIN_ID:-gemba-testnet-1}; NODE=${NODE:-tcp://localhost:26657}
RPC=${RPC_HTTP:-http://localhost:26657}; GAS_PRICES=${GAS_PRICES:-1000000000agmb}
LOG=${LOG_FILE:-/var/log/gemba-validator-auto.log}
# --- watchdog (layer 1/2) config, with safe defaults ---
ENABLE_AUTO_RESTART=${ENABLE_AUTO_RESTART:-true}      # set false to detect-only (log, never restart)
RESTART_CMD=${RESTART_CMD:-systemctl restart gembad}  # Contabo: "systemctl restart gembad-val" ; home/docker: "systemctl restart gembad"
TIP_EVM_RPCS=${TIP_EVM_RPCS:-}                         # space-sep public EVM RPC URLs for the network tip (optional)
LOCAL_EVM_RPC=${LOCAL_EVM_RPC:-http://localhost:8545} # local EVM RPC, for an apples-to-apples tip gap (optional)
STUCK_BEHIND_BLOCKS=${STUCK_BEHIND_BLOCKS:-100}        # behind the tip by more than this AND not advancing => stuck
SYNC_MARGIN_BLOCKS=${SYNC_MARGIN_BLOCKS:-25}           # within this of the tip counts as "caught up" for unjail
RESTART_COOLDOWN_SEC=${RESTART_COOLDOWN_SEC:-900}      # min seconds between restarts (backoff)
MAX_CONSECUTIVE_RESTARTS=${MAX_CONSECUTIVE_RESTARTS:-4} # after this many with no recovery, STOP and alert (disk/corruption won't fix by restart)
STATE_FILE=${STATE_FILE:-/var/lib/gemba/auto-unjail.state}
NOTIFY_CMD=${NOTIFY_CMD:-}                             # optional: eval'd as `$NOTIFY_CMD "<message>"` on restart / give-up

COMMON="--home $HOME_DIR --keyring-backend $KB --chain-id $CHAIN_ID --node $NODE"
KR="--home $HOME_DIR --keyring-backend $KB"   # `keys show` rejects --chain-id/--node
TX="--gas auto --gas-adjustment 1.5 --gas-prices $GAS_PRICES -y -o json"
log(){ echo "[$(date -Is)] watchdog: $*" >>"$LOG"; }
notify(){ [ -n "$NOTIFY_CMD" ] && eval "$NOTIFY_CMD \"gemba-validator: $*\"" >/dev/null 2>&1 || true; }

command -v jq >/dev/null || { log "jq missing"; exit 1; }

# ---- state (last height seen, last restart epoch, consecutive restart count) ----
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
LAST_HEIGHT=0; LAST_RESTART=0; CONSEC_RESTARTS=0
[ -f "$STATE_FILE" ] && . "$STATE_FILE" 2>/dev/null || true
save_state(){ printf 'LAST_HEIGHT=%s\nLAST_RESTART=%s\nCONSEC_RESTARTS=%s\n' \
              "${1:-$LAST_HEIGHT}" "${2:-$LAST_RESTART}" "${3:-$CONSEC_RESTARTS}" >"$STATE_FILE"; }
now_epoch(){ date +%s; }

# ---- gather LOCAL signals (always available: the node's own RPC) ----
peers=$(curl -s --max-time 5 "$RPC/net_info" | jq -r '.result.n_peers // "unknown"' 2>/dev/null || echo unknown)
lstatus=$(curl -s --max-time 5 "$RPC/status" 2>/dev/null || echo '')
height=$(echo "$lstatus" | jq -r '.result.sync_info.latest_block_height // "0"' 2>/dev/null || echo 0)
# Read the boolean DIRECTLY — jq's `//` treats boolean `false` as empty, so `.catching_up // "x"`
# would wrongly yield "x" for a caught-up node (the exact footgun the old script warned about).
# Prints literal "false"/"true"; unreachable RPC -> empty -> handled as "not confirmed synced".
catching=$(echo "$lstatus" | jq -r '.result.sync_info.catching_up' 2>/dev/null)
[ "$catching" = "false" ] || [ "$catching" = "true" ] || catching=unknown
[[ "$height"  =~ ^[0-9]+$ ]] || height=0
[[ "$peers"   =~ ^[0-9]+$ ]] || peers=-1   # -1 = RPC unreachable (node down / starting)

# ---- external network tip via PUBLIC EVM RPC (optional) ----
evm_height(){ # $1=url -> decimal height or empty
  local r; r=$(curl -s --max-time 6 -X POST "$1" -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' 2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null)
  [[ "$r" =~ ^0x[0-9a-fA-F]+$ ]] && printf '%d' "$r" || true
}
TIP=""; for u in $TIP_EVM_RPCS; do TIP=$(evm_height "$u"); [ -n "$TIP" ] && break; done
LOCAL_EVM=""; [ -n "$LOCAL_EVM_RPC" ] && LOCAL_EVM=$(evm_height "$LOCAL_EVM_RPC")
behind=""; [ -n "$TIP" ] && [ -n "$LOCAL_EVM" ] && behind=$(( TIP - LOCAL_EVM ))

# ---- did the node advance since the previous run? (frozen == stuck, whatever catching_up claims) ----
first_run=0; [ "${LAST_HEIGHT:-0}" = "0" ] && first_run=1
moved=1; [ "$first_run" = "0" ] && [ "$height" = "$LAST_HEIGHT" ] && moved=0
save_state "$height" "$LAST_RESTART" "$CONSEC_RESTARTS"   # remember height for next run's freeze check

# =====================================================================================
# LAYER 1 — DETECT STUCK, then RESTART (with backoff + cap)
# =====================================================================================
stuck="";
if   [ "$peers" = "-1" ];                            then stuck="RPC unreachable (node down/starting)"
elif [ "$peers" = "0" ];                             then stuck="0 peers (lost connectivity)"
elif [ "$first_run" = "0" ] && [ "$moved" = "0" ];   then stuck="height frozen at $height between runs"
elif [ -n "$behind" ] && [ "$behind" -gt "$STUCK_BEHIND_BLOCKS" ] && [ "$moved" = "0" ]; then
     stuck="behind tip by $behind blocks and not advancing"
fi

if [ -n "$stuck" ]; then
  if [ "$ENABLE_AUTO_RESTART" != "true" ]; then
    log "STUCK ($stuck) — auto-restart disabled, leaving for a human"; notify "STUCK, restart disabled: $stuck"; exit 0
  fi
  nowe=$(now_epoch); since=$(( nowe - ${LAST_RESTART:-0} ))
  if [ "${CONSEC_RESTARTS:-0}" -ge "$MAX_CONSECUTIVE_RESTARTS" ]; then
    log "STUCK ($stuck) — already restarted ${CONSEC_RESTARTS}x with no recovery; NOT restarting (likely disk/corruption) — NEEDS HUMAN"
    notify "give up after ${CONSEC_RESTARTS} restarts: $stuck"; exit 0
  fi
  if [ "$since" -lt "$RESTART_COOLDOWN_SEC" ]; then
    log "STUCK ($stuck) — in restart cooldown (${since}s < ${RESTART_COOLDOWN_SEC}s), waiting"; exit 0
  fi
  log "STUCK ($stuck) — restarting node: $RESTART_CMD  (restart #$(( ${CONSEC_RESTARTS:-0} + 1 )))"
  notify "restarting node: $stuck"
  if $RESTART_CMD; then
    save_state "$height" "$nowe" "$(( ${CONSEC_RESTARTS:-0} + 1 ))"
    log "restart issued — will re-check next run once it re-dials peers and catches up"
  else
    log "restart command FAILED ($RESTART_CMD) — check the service unit"; notify "restart command failed"
  fi
  exit 0
fi

# not stuck -> clear the restart counter so a future transient blip gets a fresh budget
[ "${CONSEC_RESTARTS:-0}" != "0" ] && { save_state "$height" "$LAST_RESTART" 0; log "node healthy again — restart counter reset"; }

# =====================================================================================
# LAYER 2 — SYNC GATE (must be genuinely caught up before we touch unjail)
# =====================================================================================
synced=1
[ "$peers" -gt 0 ] 2>/dev/null || synced=0
[ "$catching" = "false" ] || synced=0
if [ -n "$behind" ]; then
  [ "$behind" -le "$SYNC_MARGIN_BLOCKS" ] || synced=0     # precise gap when we have both EVM heights
elif [ "$first_run" = "0" ]; then
  [ "$moved" = "1" ] || synced=0                          # else at least require forward progress
fi

# =====================================================================================
# LAYER 3 — UNJAIL (jail status read locally, but ONLY now that sync is confirmed)
# =====================================================================================
valoper=$($GEMBAD keys show "$KEY" --bech val -a $KR 2>/dev/null) || { log "cannot read valoper (key $KEY)"; exit 1; }
[ -z "$valoper" ] && { log "cannot read valoper (empty) — key $KEY missing?"; exit 1; }

# `(.validator // .)` handles both SDK shapes ({"validator":{…}} or the bare object); read the
# boolean directly (no `//` fallback, same false-is-empty footgun). Prints "true"/"false"/"null".
jailed=$($GEMBAD query staking validator "$valoper" --node "$NODE" -o json 2>/dev/null \
         | jq -r '(.validator // .).jailed' 2>/dev/null)
# Email once per jail episode (marker file), and once on recovery — no per-tick spam.
JAIL_MARK="${STATE_FILE}.jailed"
if [ "$jailed" != "true" ]; then
  [ -f "$JAIL_MARK" ] && { notify "validator recovered — no longer jailed, signing again"; log "recovered — jail cleared"; rm -f "$JAIL_MARK"; }
  exit 0   # not jailed (or query unreachable) -> nothing to do (healthy, signing)
fi
[ -f "$JAIL_MARK" ] || { notify "validator JAILED (downtime) — watchdog recovering (restart/sync/unjail)"; : > "$JAIL_MARK"; }

if [ "$synced" != "1" ]; then
  log "jailed but not fully synced yet (peers=$peers catching_up=$catching behind=${behind:-?}) — waiting to unjail"; exit 0
fi

if $GEMBAD tx slashing unjail --from "$KEY" $COMMON $TX >/dev/null 2>&1; then
  log "unjail submitted (node synced: peers=$peers behind=${behind:-0})"
else
  log "unjail not accepted yet (inside jail window, or tombstoned/double-sign) — will retry"
fi
