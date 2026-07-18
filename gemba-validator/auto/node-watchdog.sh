#!/usr/bin/env bash
# GembaBlockchain generic NODE watchdog — detect-stuck -> restart. NO unjail.
#
# The lightweight sibling of auto-unjail.sh: it runs only layers 1-2 (detect + restart) and is
# meant for NON-validator full nodes — the archive, an explorer's RPC source, a public RPC — that
# have no operator key and never get jailed, but CAN silently freeze (lost peers / stalled sync)
# while the process stays alive, so systemd's Restart=always never fires. Same stuck signals the
# validator watchdog uses: RPC unreachable, 0 peers, height not advancing between runs, or (if a
# public tip is configured) far behind the network. Backoff + a hard cap prevent restart storms;
# after the cap it stops and alerts (a restart can't fix a full disk — see disk-guard.sh).
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _f in /etc/gemba/node-watchdog.env "$DIR/node-watchdog.env"; do [ -f "$_f" ] && . "$_f" && break; done
RPC=${RPC_HTTP:-http://localhost:26657}
ENABLE_AUTO_RESTART=${ENABLE_AUTO_RESTART:-true}
RESTART_CMD=${RESTART_CMD:-systemctl restart gembad-archive}
TIP_EVM_RPCS=${TIP_EVM_RPCS:-}
LOCAL_EVM_RPC=${LOCAL_EVM_RPC:-http://localhost:8545}
STUCK_BEHIND_BLOCKS=${STUCK_BEHIND_BLOCKS:-100}
RESTART_COOLDOWN_SEC=${RESTART_COOLDOWN_SEC:-900}
MAX_CONSECUTIVE_RESTARTS=${MAX_CONSECUTIVE_RESTARTS:-4}
STATE_FILE=${STATE_FILE:-/var/lib/gemba/node-watchdog.state}
LOG=${LOG_FILE:-/var/log/gemba-node-watchdog.log}
NOTIFY_CMD=${NOTIFY_CMD:-}
LABEL=${NODE_LABEL:-node}
log(){ echo "[$(date -Is)] node-watchdog($LABEL): $*" >>"$LOG"; }
notify(){ [ -n "$NOTIFY_CMD" ] && eval "$NOTIFY_CMD \"gemba-$LABEL: $*\"" >/dev/null 2>&1 || true; }
command -v jq >/dev/null || { log "jq missing"; exit 1; }

mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
LAST_HEIGHT=0; LAST_RESTART=0; CONSEC_RESTARTS=0
[ -f "$STATE_FILE" ] && . "$STATE_FILE" 2>/dev/null || true
save_state(){ printf 'LAST_HEIGHT=%s\nLAST_RESTART=%s\nCONSEC_RESTARTS=%s\n' \
              "${1:-$LAST_HEIGHT}" "${2:-$LAST_RESTART}" "${3:-$CONSEC_RESTARTS}" >"$STATE_FILE"; }

# ---- local signals ----
peers=$(curl -s --max-time 5 "$RPC/net_info" | jq -r '.result.n_peers // "unknown"' 2>/dev/null || echo unknown)
lstatus=$(curl -s --max-time 5 "$RPC/status" 2>/dev/null || echo '')
height=$(echo "$lstatus" | jq -r '.result.sync_info.latest_block_height // "0"' 2>/dev/null || echo 0)
[[ "$height" =~ ^[0-9]+$ ]] || height=0
[[ "$peers"  =~ ^[0-9]+$ ]] || peers=-1

# ---- external tip via public EVM RPC (optional) ----
evm_height(){ local r; r=$(curl -s --max-time 6 -X POST "$1" -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' 2>/dev/null | jq -r '.result // empty' 2>/dev/null)
  [[ "$r" =~ ^0x[0-9a-fA-F]+$ ]] && printf '%d' "$r" || true; }
TIP=""; for u in $TIP_EVM_RPCS; do TIP=$(evm_height "$u"); [ -n "$TIP" ] && break; done
LOCAL_EVM=""; [ -n "$LOCAL_EVM_RPC" ] && LOCAL_EVM=$(evm_height "$LOCAL_EVM_RPC")
behind=""; [ -n "$TIP" ] && [ -n "$LOCAL_EVM" ] && behind=$(( TIP - LOCAL_EVM ))

first_run=0; [ "${LAST_HEIGHT:-0}" = "0" ] && first_run=1
moved=1; [ "$first_run" = "0" ] && [ "$height" = "$LAST_HEIGHT" ] && moved=0
save_state "$height" "$LAST_RESTART" "$CONSEC_RESTARTS"

# ---- DETECT ----
stuck=""
if   [ "$peers" = "-1" ];                          then stuck="RPC unreachable (node down/starting)"
elif [ "$peers" = "0" ];                           then stuck="0 peers (lost connectivity)"
elif [ "$first_run" = "0" ] && [ "$moved" = "0" ]; then stuck="height frozen at $height between runs"
elif [ -n "$behind" ] && [ "$behind" -gt "$STUCK_BEHIND_BLOCKS" ] && [ "$moved" = "0" ]; then
     stuck="behind tip by $behind blocks and not advancing"
fi

if [ -z "$stuck" ]; then
  [ "${CONSEC_RESTARTS:-0}" != "0" ] && { save_state "$height" "$LAST_RESTART" 0; log "healthy again — restart counter reset"; }
  exit 0
fi

# ---- RESTART (backoff + cap) ----
if [ "$ENABLE_AUTO_RESTART" != "true" ]; then log "STUCK ($stuck) — auto-restart disabled"; notify "STUCK: $stuck"; exit 0; fi
nowe=$(date +%s); since=$(( nowe - ${LAST_RESTART:-0} ))
if [ "${CONSEC_RESTARTS:-0}" -ge "$MAX_CONSECUTIVE_RESTARTS" ]; then
  log "STUCK ($stuck) — already restarted ${CONSEC_RESTARTS}x with no recovery; NOT restarting (likely disk/corruption) — NEEDS HUMAN"
  notify "give up after ${CONSEC_RESTARTS} restarts: $stuck"; exit 0
fi
if [ "$since" -lt "$RESTART_COOLDOWN_SEC" ]; then log "STUCK ($stuck) — in cooldown (${since}s<${RESTART_COOLDOWN_SEC}s), waiting"; exit 0; fi
log "STUCK ($stuck) — restarting: $RESTART_CMD (restart #$(( ${CONSEC_RESTARTS:-0} + 1 )))"; notify "restarting: $stuck"
if $RESTART_CMD; then
  save_state "$height" "$nowe" "$(( ${CONSEC_RESTARTS:-0} + 1 ))"
  log "restart issued — will re-check next run once it re-dials peers and catches up"
else
  log "restart command FAILED ($RESTART_CMD)"; notify "restart command failed"
fi
