#!/usr/bin/env bash
# gemba-alert-email.sh "<message>" — send one operator alert email via SMTP.
#
# The shared notify sink for the box ops daemons (disk-guard, node-watchdog, the validator
# watchdog's jail/give-up events). Reuses the SAME gembascan.io contact-form SMTP account that
# monitoring/alertmanager.yml uses, so email works even when the full Prometheus stack is not up.
#
# SECRET HYGIENE (repo is public): the SMTP password is NEVER in git. It is read from a
# root-owned, gitignored file provisioned on the box (default /etc/gemba/smtp_password, chmod 600).
# Everything else is in /etc/gemba/notify.env. If email is not configured the script is a silent
# no-op (exit 0) — callers wire it as NOTIFY_CMD and must never fail just because email is unset.
set -uo pipefail
MSG="${1:-gemba alert}"
[ -f /etc/gemba/notify.env ] && . /etc/gemba/notify.env || exit 0
: "${SMTP_HOST:=}"; : "${SMTP_PORT:=587}"; : "${SMTP_FROM:=}"; : "${SMTP_USER:=${SMTP_FROM:-}}"
: "${SMTP_PASS_FILE:=/etc/gemba/smtp_password}"; : "${ALERT_TO:=}"; : "${ALERT_SUBJECT_PREFIX:=[GembaChain alert]}"
{ [ -z "$SMTP_HOST" ] || [ -z "$SMTP_FROM" ] || [ -z "$ALERT_TO" ] || [ ! -f "$SMTP_PASS_FILE" ]; } && exit 0
PASS="$(cat "$SMTP_PASS_FILE" 2>/dev/null)"; [ -z "$PASS" ] && exit 0
HOST="$(hostname 2>/dev/null || echo node)"
body="$(printf 'From: %s\r\nTo: %s\r\nSubject: %s %s\r\nDate: %s\r\n\r\n%s\r\n' \
  "$SMTP_FROM" "$ALERT_TO" "$ALERT_SUBJECT_PREFIX" "$HOST" "$(date -R)" "$MSG")"
if curl --silent --show-error --max-time 25 --url "smtp://$SMTP_HOST:$SMTP_PORT" --ssl-reqd \
     --mail-from "$SMTP_FROM" --mail-rcpt "$ALERT_TO" --user "$SMTP_USER:$PASS" \
     --upload-file <(printf '%s' "$body") >/dev/null 2>&1; then
  logger -t gemba-alert-email "sent to $ALERT_TO: $MSG" 2>/dev/null || true
else
  logger -t gemba-alert-email "FAILED to send: $MSG" 2>/dev/null || true
fi
exit 0
