# watchdog-lib.sh — the SHARED layer-1 engine of the gemba watchdogs. SOURCED, not executed.
#
# Used by auto-unjail.sh (validator: layers 1-3) and node-watchdog.sh (generic node:
# layers 1-2 only). Extracted 2026-07-19 — the two scripts carried byte-identical copies
# of this logic, so a fix to one silently missed the other.
#
# Contract for callers (define BEFORE calling these functions):
#   log()/notify()                                — per-script prefixes/sinks
#   RPC STATE_FILE TIP_EVM_RPCS LOCAL_EVM_RPC     — config (with defaults set)
#   STUCK_BEHIND_BLOCKS RESTART_COOLDOWN_SEC MAX_CONSECUTIVE_RESTARTS
#   ENABLE_AUTO_RESTART RESTART_CMD
# Everything here must stay correct under BOTH `set -euo pipefail` (auto-unjail) and
# `set -uo pipefail` (node-watchdog): every probe guards its own failure.

# --- single-instance lock. Defense-in-depth beyond systemd's one-instance-per-unit
#     guarantee: protects against a MANUAL run racing the timer. Non-blocking — the
#     second instance logs and exits 0 (healthy no-op, not an error).
wd_acquire_lock(){ # $1 = lock name
  local lk="/run/lock/gemba-$1.lock"
  exec 9>"$lk" 2>/dev/null || { lk="/tmp/gemba-$1.lock"; exec 9>"$lk"; }
  flock -n 9 || { log "another instance holds $lk — exiting"; exit 0; }
}

# --- state (LAST_HEIGHT / LAST_RESTART / CONSEC_RESTARTS) ---
wd_load_state(){
  mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || true
  LAST_HEIGHT=0; LAST_RESTART=0; CONSEC_RESTARTS=0
  [ -f "$STATE_FILE" ] && . "$STATE_FILE" 2>/dev/null || true
  return 0
}
# Atomic write (temp+mv): a mid-write kill must never leave a truncated file that the
# next run would `source`.
save_state(){ local t; t=$(mktemp "${STATE_FILE}.XXXXXX" 2>/dev/null) || return 0
  printf 'LAST_HEIGHT=%s\nLAST_RESTART=%s\nCONSEC_RESTARTS=%s\n' \
    "${1:-$LAST_HEIGHT}" "${2:-$LAST_RESTART}" "${3:-$CONSEC_RESTARTS}" >"$t" && mv -f "$t" "$STATE_FILE"; }

now_epoch(){ date +%s; }

# --- LOCAL node signals -> peers, lstatus, height, catching ---
wd_gather_local(){
  peers=$(curl -s --max-time 5 "$RPC/net_info" | jq -r '.result.n_peers // "unknown"' 2>/dev/null || echo unknown)
  lstatus=$(curl -s --max-time 5 "$RPC/status" 2>/dev/null || echo '')
  height=$(echo "$lstatus" | jq -r '.result.sync_info.latest_block_height // "0"' 2>/dev/null || echo 0)
  # Read the boolean DIRECTLY — jq's `//` treats boolean `false` as empty, so
  # `.catching_up // "x"` would wrongly yield "x" for a caught-up node.
  # Prints literal "false"/"true"; unreachable RPC -> empty -> "not confirmed synced".
  catching=$(echo "$lstatus" | jq -r '.result.sync_info.catching_up' 2>/dev/null)
  [ "$catching" = "false" ] || [ "$catching" = "true" ] || catching=unknown
  [[ "$height" =~ ^[0-9]+$ ]] || height=0
  [[ "$peers"  =~ ^[0-9]+$ ]] || peers=-1   # -1 = RPC unreachable (node down / starting)
  return 0
}

# --- external network tip via PUBLIC EVM RPC (optional) -> TIP, LOCAL_EVM, behind ---
evm_height(){ # $1=url -> decimal height or empty
  local r; r=$(curl -s --max-time 6 -X POST "$1" -H 'content-type: application/json' \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","id":1}' 2>/dev/null \
        | jq -r '.result // empty' 2>/dev/null)
  [[ "$r" =~ ^0x[0-9a-fA-F]+$ ]] && printf '%d' "$r" || true
}
wd_gather_tip(){
  TIP=""; local u; for u in $TIP_EVM_RPCS; do TIP=$(evm_height "$u"); [ -n "$TIP" ] && break; done
  LOCAL_EVM=""; [ -n "$LOCAL_EVM_RPC" ] && LOCAL_EVM=$(evm_height "$LOCAL_EVM_RPC")
  behind=""; [ -n "$TIP" ] && [ -n "$LOCAL_EVM" ] && behind=$(( TIP - LOCAL_EVM ))
  return 0   # the && list above returns 1 when no tip is configured — must not kill a `set -e` caller
}

# --- did the node advance since the previous run? (frozen == stuck, whatever
#     catching_up claims) -> first_run, moved; persists height for the next run ---
wd_freeze_check(){
  first_run=0; [ "${LAST_HEIGHT:-0}" = "0" ] && first_run=1
  moved=1; [ "$first_run" = "0" ] && [ "$height" = "$LAST_HEIGHT" ] && moved=0
  save_state "$height" "$LAST_RESTART" "$CONSEC_RESTARTS"
  return 0
}

# --- LAYER-1 detect -> stuck ("" = healthy) ---
wd_detect_stuck(){
  stuck=""
  if   [ "$peers" = "-1" ];                            then stuck="RPC unreachable (node down/starting)"
  elif [ "$peers" = "0" ];                             then stuck="0 peers (lost connectivity)"
  elif [ "$first_run" = "0" ] && [ "$moved" = "0" ];   then stuck="height frozen at $height between runs"
  elif [ -n "$behind" ] && [ "$behind" -gt "$STUCK_BEHIND_BLOCKS" ] && [ "$moved" = "0" ]; then
       stuck="behind tip by $behind blocks and not advancing"
  fi
  return 0
}

# --- LAYER-1 restart flow (backoff + hard cap + give-up alert). Call ONLY when
#     $stuck is non-empty. Always exits the script. ---
wd_restart_flow(){
  if [ "$ENABLE_AUTO_RESTART" != "true" ]; then
    log "STUCK ($stuck) — auto-restart disabled, leaving for a human"; notify "STUCK, restart disabled: $stuck"; exit 0
  fi
  local nowe since; nowe=$(now_epoch); since=$(( nowe - ${LAST_RESTART:-0} ))
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
}

# --- clear the restart counter when healthy, so a future transient blip gets a
#     fresh restart budget ---
wd_reset_restart_counter(){
  [ "${CONSEC_RESTARTS:-0}" != "0" ] && { save_state "$height" "$LAST_RESTART" 0; log "node healthy again — restart counter reset"; }
  return 0
}
