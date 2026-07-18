#!/usr/bin/env bash
# gemba-disk-guard.sh — disk-usage alarm guard for EVERY gemba box.
#
# Why: a full disk is the one failure systemd's Restart=always makes WORSE — the node crashes on
# write, restarts, crashes again = a silent crash-loop (the .82 2026-07-15 incident). This guard
# watches the mount(s) and ALERTS a human (email + journald) BEFORE that happens. It does NOT
# delete chain data (never destructive by default). Optional first-aid: on CRIT it can vacuum
# journald to a cap (safe, reversible) if journald is the hog — off unless DISK_GUARD_VACUUM_JOURNAL=true.
#
# Anti-spam: emails on first crossing of WARN/CRIT and then at most once per DISK_ALERT_REPEAT_SEC
# while still over threshold; clears (and emails an all-clear) when usage drops back below WARN.
set -uo pipefail
[ -f /etc/gemba/disk-guard.env ] && . /etc/gemba/disk-guard.env || true
MOUNTS=${DISK_MOUNTS:-/}
WARN_PCT=${DISK_WARN_PCT:-85}
CRIT_PCT=${DISK_CRIT_PCT:-95}
REPEAT=${DISK_ALERT_REPEAT_SEC:-21600}          # re-email at most every 6h while still over threshold
STATE_DIR=${DISK_STATE_DIR:-/var/lib/gemba}
LOG=${LOG_FILE:-/var/log/gemba-disk-guard.log}
NOTIFY_CMD=${NOTIFY_CMD:-/usr/local/bin/gemba-alert-email.sh}
VACUUM=${DISK_GUARD_VACUUM_JOURNAL:-false}
JCAP=${DISK_GUARD_JOURNAL_CAP:-200M}
mkdir -p "$STATE_DIR" 2>/dev/null || true
log(){ echo "[$(date -Is)] disk-guard: $*" >>"$LOG"; }
email(){ [ -n "$NOTIFY_CMD" ] && [ -x "${NOTIFY_CMD%% *}" ] && $NOTIFY_CMD "$1" >/dev/null 2>&1 || true; }
alert(){ logger -t gemba-disk-guard -p daemon.warning "$1" 2>/dev/null || true; email "$1"; }

for m in $MOUNTS; do
  pct=$(df --output=pcent "$m" 2>/dev/null | tail -1 | tr -dc '0-9')
  [ -z "$pct" ] && { log "cannot read usage for $m"; continue; }
  avail=$(df -h --output=avail "$m" 2>/dev/null | tail -1 | tr -d ' ')
  key=$(echo "$m" | sed 's#[/ ]#_#g'); [ "$key" = "_" ] && key=root
  SF="$STATE_DIR/disk-guard.$key.state"
  PREV_LEVEL=ok; PREV_TS=0
  [ -f "$SF" ] && . "$SF" 2>/dev/null || true
  now=$(date +%s)

  level=ok
  [ "$pct" -ge "$WARN_PCT" ] && level=warn
  [ "$pct" -ge "$CRIT_PCT" ] && level=crit

  if [ "$level" = "ok" ]; then
    if [ "$PREV_LEVEL" != "ok" ]; then
      log "RECOVERED $m back to ${pct}% (avail $avail)"; alert "RECOVERED: $(hostname) $m back to ${pct}% used ($avail free)"
    fi
    printf 'PREV_LEVEL=ok\nPREV_TS=%s\n' "$now" >"$SF"; continue
  fi

  # over threshold — decide whether to (re)notify
  escalated=0; [ "$PREV_LEVEL" = "ok" ] && escalated=1
  [ "$PREV_LEVEL" = "warn" ] && [ "$level" = "crit" ] && escalated=1
  due=0; [ $((now - PREV_TS)) -ge "$REPEAT" ] && due=1

  if [ "$level" = "crit" ]; then
    log "CRIT $m at ${pct}% (avail $avail)"
    if [ "$VACUUM" = "true" ]; then journalctl --vacuum-size="$JCAP" >/dev/null 2>&1 && log "first-aid: vacuumed journald to $JCAP"; fi
    if [ "$escalated" = "1" ] || [ "$due" = "1" ]; then
      alert "CRITICAL: $(hostname) disk $m ${pct}% full (only $avail free) — node write-crash-loop risk, act NOW"
      printf 'PREV_LEVEL=crit\nPREV_TS=%s\n' "$now" >"$SF"
    else printf 'PREV_LEVEL=crit\nPREV_TS=%s\n' "$PREV_TS" >"$SF"; fi
  else # warn
    log "WARN $m at ${pct}% (avail $avail)"
    if [ "$escalated" = "1" ] || [ "$due" = "1" ]; then
      alert "WARNING: $(hostname) disk $m ${pct}% full ($avail free) — review pruning/capacity"
      printf 'PREV_LEVEL=warn\nPREV_TS=%s\n' "$now" >"$SF"
    else printf 'PREV_LEVEL=warn\nPREV_TS=%s\n' "$PREV_TS" >"$SF"; fi
  fi
done
