#!/usr/bin/env bash
# Install the GembaBlockchain validator auto-ops daemons (auto-unjail + auto-compound)
# on a validator box. Run as root on the validator. Idempotent.
#
#   sudo ./install-validator-auto.sh
#
# It: installs deps (jq, bc), copies the scripts to /usr/local/bin, the config to
# /etc/gemba/validator-auto.env (preserving an existing one), the systemd units, and
# enables both timers. Edit /etc/gemba/validator-auto.env first if your paths differ.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ "$(id -u)" = "0" ] || { echo "run as root"; exit 1; }

echo "==> deps"
if command -v apt-get >/dev/null; then apt-get install -y -q jq bc >/dev/null 2>&1 || true; fi
command -v jq >/dev/null || { echo "ERROR: jq not installed"; exit 1; }
command -v bc >/dev/null || { echo "ERROR: bc not installed"; exit 1; }

echo "==> scripts -> /usr/local/bin (+ shared watchdog lib -> /usr/local/lib/gemba)"
install -m 0755 "$DIR/auto-unjail.sh"      /usr/local/bin/gemba-auto-unjail.sh
install -m 0755 "$DIR/auto-compound.sh"    /usr/local/bin/gemba-auto-compound.sh
install -m 0755 "$DIR/disk-guard.sh"       /usr/local/bin/gemba-disk-guard.sh
install -m 0755 "$DIR/gemba-alert-email.sh" /usr/local/bin/gemba-alert-email.sh
install -D -m 0644 "$DIR/watchdog-lib.sh"  /usr/local/lib/gemba/watchdog-lib.sh

echo "==> logrotate -> /etc/logrotate.d/gemba"
install -m 0644 "$DIR/logrotate-gemba" /etc/logrotate.d/gemba

echo "==> config -> /etc/gemba/*.env (existing files kept)"
mkdir -p /etc/gemba /var/lib/gemba
for e in validator-auto disk-guard notify; do
  src="$DIR/$e.env"; [ -f "$src" ] || src="$DIR/$e.env.example"   # notify ships as .example (no real address in the public repo)
  if [ -f /etc/gemba/$e.env ]; then echo "    keeping existing /etc/gemba/$e.env"
  else install -m 0644 "$src" /etc/gemba/$e.env; echo "    installed /etc/gemba/$e.env — EDIT IT (RESTART_CMD, SMTP host, ALERT_TO, etc.)"; fi
done
echo "    NOTE: email is inert until you provision the SMTP secret:"
echo "          printf %s '<smtp-password>' > /etc/gemba/smtp_password && chmod 600 /etc/gemba/smtp_password"
echo "          and set SMTP_HOST + ALERT_TO in /etc/gemba/notify.env."

echo "==> systemd units"
install -m 0644 "$DIR"/systemd/gemba-auto-*.service     /etc/systemd/system/
install -m 0644 "$DIR"/systemd/gemba-auto-*.timer       /etc/systemd/system/
install -m 0644 "$DIR"/systemd/gemba-disk-guard.service /etc/systemd/system/
install -m 0644 "$DIR"/systemd/gemba-disk-guard.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gemba-auto-unjail.timer gemba-auto-compound.timer gemba-disk-guard.timer

echo "==> done. Timers:"
systemctl list-timers 'gemba-auto-*' --no-pager || true
echo "Logs: tail -f $(grep -oE '^LOG_FILE=.*' /etc/gemba/validator-auto.env | cut -d= -f2 2>/dev/null || echo /var/log/gemba-validator-auto.log)"
