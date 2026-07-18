#!/usr/bin/env bash
# Install GembaBlockchain box ops on a NON-validator box (archive, explorer, public RPC):
#   - gemba-disk-guard  (always) — disk-usage alarm -> email before a full disk crash-loops things
#   - gemba-alert-email (always) — the shared SMTP email sink
#   - gemba-node-watchdog (opt-in with --with-watchdog) — detect-stuck -> restart, for gembad full
#     nodes (archive / RPC source). Do NOT use on the explorer's Blockscout (not a gembad node).
#
#   sudo ./install-node-ops.sh [--with-watchdog]
#
# Idempotent; keeps any existing /etc/gemba/*.env. Edit the env files after (RESTART_CMD, the
# node's real RPC port, disk MOUNTS, SMTP host) and provision the SMTP secret — see the echo at end.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" = "0" ] || { echo "run as root"; exit 1; }
WITH_WD=0; [ "${1:-}" = "--with-watchdog" ] && WITH_WD=1

command -v apt-get >/dev/null && apt-get install -y -q jq curl >/dev/null 2>&1 || true
command -v jq >/dev/null || { echo "ERROR: jq not installed"; exit 1; }

echo "==> scripts"
install -m 0755 "$DIR/gemba-alert-email.sh" /usr/local/bin/gemba-alert-email.sh
install -m 0755 "$DIR/disk-guard.sh"        /usr/local/bin/gemba-disk-guard.sh
if [ "$WITH_WD" = 1 ]; then
  install -m 0755 "$DIR/node-watchdog.sh" /usr/local/bin/gemba-node-watchdog.sh
  install -D -m 0644 "$DIR/watchdog-lib.sh" /usr/local/lib/gemba/watchdog-lib.sh
fi

echo "==> logrotate -> /etc/logrotate.d/gemba"
install -m 0644 "$DIR/logrotate-gemba" /etc/logrotate.d/gemba

echo "==> config -> /etc/gemba (existing kept)"
mkdir -p /etc/gemba /var/lib/gemba
envs="notify disk-guard"; [ "$WITH_WD" = 1 ] && envs="$envs node-watchdog"
for e in $envs; do
  src="$DIR/$e.env"; [ -f "$src" ] || src="$DIR/$e.env.example"   # notify ships as .example (no real address in the public repo)
  if [ -f /etc/gemba/$e.env ]; then echo "    keeping /etc/gemba/$e.env"
  else install -m 0644 "$src" /etc/gemba/$e.env; echo "    installed /etc/gemba/$e.env — EDIT (RESTART_CMD + real RPC port, disk MOUNTS, SMTP host, ALERT_TO)"; fi
done

echo "==> systemd units + timers"
install -m 0644 "$DIR"/systemd/gemba-disk-guard.service "$DIR"/systemd/gemba-disk-guard.timer /etc/systemd/system/
timers="gemba-disk-guard.timer"
if [ "$WITH_WD" = 1 ]; then
  install -m 0644 "$DIR"/systemd/gemba-node-watchdog.service "$DIR"/systemd/gemba-node-watchdog.timer /etc/systemd/system/
  timers="$timers gemba-node-watchdog.timer"
fi
systemctl daemon-reload
# shellcheck disable=SC2086
systemctl enable --now $timers

echo "==> done. Timers:"; systemctl list-timers 'gemba-*' --no-pager || true
echo "Activate email: printf %s '<smtp-password>' > /etc/gemba/smtp_password && chmod 600 /etc/gemba/smtp_password ; set SMTP_HOST in /etc/gemba/notify.env"
[ "$WITH_WD" = 1 ] && echo "Watchdog: set RESTART_CMD + RPC_HTTP (this node's REAL CometBFT rpc port — grep '^laddr' config.toml) in /etc/gemba/node-watchdog.env"
