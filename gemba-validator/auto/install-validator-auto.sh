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

echo "==> scripts -> /usr/local/bin"
install -m 0755 "$DIR/auto-unjail.sh"    /usr/local/bin/gemba-auto-unjail.sh
install -m 0755 "$DIR/auto-compound.sh"  /usr/local/bin/gemba-auto-compound.sh

echo "==> config -> /etc/gemba/validator-auto.env"
mkdir -p /etc/gemba
if [ -f /etc/gemba/validator-auto.env ]; then
  echo "    keeping existing /etc/gemba/validator-auto.env"
else
  install -m 0644 "$DIR/validator-auto.env" /etc/gemba/validator-auto.env
  echo "    installed default — EDIT IT if your CHAIN_ID/home/key differ"
fi

echo "==> systemd units"
install -m 0644 "$DIR"/systemd/gemba-auto-*.service /etc/systemd/system/
install -m 0644 "$DIR"/systemd/gemba-auto-*.timer   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now gemba-auto-unjail.timer gemba-auto-compound.timer

echo "==> done. Timers:"
systemctl list-timers 'gemba-auto-*' --no-pager || true
echo "Logs: tail -f $(grep -oE '^LOG_FILE=.*' /etc/gemba/validator-auto.env | cut -d= -f2 2>/dev/null || echo /var/log/gemba-validator-auto.log)"
