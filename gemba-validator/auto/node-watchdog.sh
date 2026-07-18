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
# Deliberately no `set -e`: every probe guards its own failure, and a transient probe
# error must not abort the watchdog mid-decision.
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
# NOTIFY_CMD is run directly (word-split command + the message as ONE argument) — not eval'd.
notify(){ [ -n "$NOTIFY_CMD" ] && $NOTIFY_CMD "gemba-$LABEL: $*" >/dev/null 2>&1 || true; }
command -v jq >/dev/null || { log "jq missing"; exit 1; }

# Layer-1 engine (detect/restart/state/lock) is shared with auto-unjail.sh.
for _l in "$DIR/watchdog-lib.sh" /usr/local/lib/gemba/watchdog-lib.sh; do [ -f "$_l" ] && . "$_l" && break; done
command -v wd_detect_stuck >/dev/null || { log "watchdog-lib.sh missing (repo dir or /usr/local/lib/gemba)"; exit 1; }

wd_acquire_lock "node-watchdog-$LABEL"
wd_load_state
wd_gather_local     # -> peers, height, catching
wd_gather_tip       # -> TIP, LOCAL_EVM, behind
wd_freeze_check     # -> first_run, moved (persists height for the next run)

wd_detect_stuck
if [ -z "$stuck" ]; then
  wd_reset_restart_counter
  exit 0
fi
wd_restart_flow     # backoff + cap + give-up alert; always exits
