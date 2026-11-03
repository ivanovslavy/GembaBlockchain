#!/usr/bin/env bash
# install.sh — install gemba-chain-halt-check for the CURRENT user (no root needed): the script to
# ~/bin, a config to ~/.config/gemba-chain-halt.env (only if absent), and one crontab line that runs
# it every minute. Idempotent: re-running replaces the script and leaves config and cron alone.
#
#   ALERT_RCPT=you@example.org ./install.sh        # on the watching box (88.203.191.208, user slavy)
#
# The SMTP credentials are NOT handled here: the checker reads them at send time from SMTP_ENV
# (default ~/.permitiv-alert.env, the file permitiv-backup-watch already uses on that box).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/bin/gemba-chain-halt-check"; CONF="$HOME/.config/gemba-chain-halt.env"; LOG="$HOME/.gemba-chain-halt.log"
install -D -m 0755 "$HERE/gemba-chain-halt-check.sh" "$BIN"
if [ ! -f "$CONF" ]; then
  : "${ALERT_RCPT:?set ALERT_RCPT for the first install}"
  install -D -m 0600 /dev/null "$CONF"
  { echo "# gemba-chain-halt-check configuration (see the header of $BIN)"
    echo "ALERT_RCPT=$ALERT_RCPT"
    echo "HALT_AFTER_SEC=180"
    echo "#COMET_RPCS=\"http://127.0.0.1:26657\"   # optional local CometBFT RPC as one more source"; } >"$CONF"
fi
LINE="* * * * * $BIN >> $LOG 2>&1"
if crontab -l 2>/dev/null | grep -qF "$BIN"; then echo "cron entry already present"
else ( crontab -l 2>/dev/null; echo "# GembaChain halt alert — every minute, mails once per halt + once on recovery"; echo "$LINE" ) | crontab -
     echo "cron entry added"; fi
rc=0; "$BIN" || rc=$?; echo "first run exit=$rc (0 healthy, 1 halted, 2 isolated) — state in ~/.local/state/gemba-chain-halt, log $LOG"
