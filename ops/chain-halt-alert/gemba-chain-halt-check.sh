#!/usr/bin/env bash
# =============================================================================
# gemba-chain-halt-check.sh — e-mail when the CHAIN stops producing blocks, seen from OUTSIDE.
#
# WHY A SECOND CHECKER. gemba-validator/auto/chain-watch.sh already runs on every validator, inside
# the unjail watchdog's timer, mailing through the chain's own SMTP account. Everything about it
# shares fate with the validators: their timer, their boxes, their mail credentials. This one does
# not. It runs as an ordinary user on a box that is NOT in the consensus path, reads ONLY the public
# RPC endpoints the users read, and mails through a different account. If the validators, their
# watchdogs and their mail all go quiet together, this still speaks.
#
# RULES (the same two that keep chain-watch.sh from crying wolf):
#   1. The height is the MAX over all sources. One stale or dead RPC is not a halt.
#   2. No answer from ANY source is not a halt either — that is this box's network. Logged, no mail
#      (a box without internet could not send it anyway).
# One mail per episode (marker file) plus one on recovery.
#
# Designed for 88.203.191.208 (user slavy, cron every minute; no MTA there, so the mail goes out
# with `curl --url smtp://…`, exactly like ~/bin/permitiv-backup-watch).
#
# Configuration (environment, or the file in $CONF):
#   RPCS            space-separated EVM JSON-RPC URLs     (default: rpc1/rpc2/rpc3.gembascan.io)
#   COMET_RPCS      optional CometBFT RPC URLs (/status)  (default: none)
#   HALT_AFTER_SEC  no new block for this long => halted  (default 180)
#   ALERT_RCPT      recipient                              (required to send mail)
#   SMTP_ENV        file with SMTP_HOST/SMTP_PORT/SMTP_USER/SMTP_PASS (default ~/.permitiv-alert.env)
#   STATE_DIR       state + marker + lock                  (default ~/.local/state/gemba-chain-halt)
#   EXPECT_CHAIN_ID refuse to judge an RPC answering another chain (default 821207 = gemba-testnet-1)
# Testing without touching the chain:
#   TEST_HEIGHT=<n> pretend every source answered <n> (simulate a stale chain)
#   DRY_RUN=1       print the mail instead of sending it
# Exit: 0 healthy/quiet, 1 halted (mail sent or attempted), 2 isolated (no source answered).
# =============================================================================
set -uo pipefail
CONF=${CONF:-$HOME/.config/gemba-chain-halt.env}
# shellcheck disable=SC1090
[ -r "$CONF" ] && . "$CONF"
RPCS=${RPCS:-"https://rpc1.gembascan.io https://rpc2.gembascan.io https://rpc3.gembascan.io"}
COMET_RPCS=${COMET_RPCS:-}
HALT_AFTER_SEC=${HALT_AFTER_SEC:-180}
ALERT_RCPT=${ALERT_RCPT:-}
SMTP_ENV=${SMTP_ENV:-$HOME/.permitiv-alert.env}
STATE_DIR=${STATE_DIR:-$HOME/.local/state/gemba-chain-halt}
EXPECT_CHAIN_ID=${EXPECT_CHAIN_ID:-821207}
TEST_HEIGHT=${TEST_HEIGHT:-}
DRY_RUN=${DRY_RUN:-0}
WHO=$(hostname)
STATE="$STATE_DIR/state"; MARK="$STATE_DIR/halted"
mkdir -p "$STATE_DIR" && chmod 700 "$STATE_DIR"
exec 9>"$STATE_DIR/lock"; flock -n 9 || exit 0          # a slow previous run is still going
log(){ echo "[$(date -u +%FT%TZ)] $*"; }

j(){ curl -s --max-time 10 -X POST -H 'content-type: application/json' --data "$2" "$1" 2>/dev/null; }
best=0; srcs=0; seen=""
for u in $RPCS; do
  if [ -n "$TEST_HEIGHT" ]; then h=$TEST_HEIGHT
  else
    cid=$(j "$u" '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' | jq -r '.result // empty' 2>/dev/null)
    [ -z "$cid" ] && { seen+=" ${u#https://}=no-answer"; continue; }
    [ "$((cid))" != "$EXPECT_CHAIN_ID" ] && { seen+=" ${u#https://}=wrong-chain($((cid)))"; continue; }
    x=$(j "$u" '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' | jq -r '.result // empty' 2>/dev/null)
    case "$x" in 0x[0-9a-fA-F]*) h=$((x)) ;; *) seen+=" ${u#https://}=no-answer"; continue ;; esac
  fi
  srcs=$((srcs+1)); seen+=" ${u#https://}=$h"; [ "$h" -gt "$best" ] && best=$h
done
for u in $COMET_RPCS; do
  if [ -n "$TEST_HEIGHT" ]; then h=$TEST_HEIGHT
  else h=$(curl -s --max-time 10 "$u/status" 2>/dev/null | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null); fi
  case "$h" in ''|*[!0-9]*) seen+=" ${u#http*://}=no-answer"; continue ;; esac
  srcs=$((srcs+1)); seen+=" ${u#http*://}=$h"; [ "$h" -gt "$best" ] && best=$h
done

if [ "$srcs" -eq 0 ]; then log "no source answered —$seen — this box looks isolated; NOT a halt"; exit 2; fi

now=$(date +%s); prev_h=0; prev_t=$now
[ -r "$STATE" ] && read -r prev_h prev_t <"$STATE"
case "$prev_h" in ''|*[!0-9]*) prev_h=0 ;; esac
case "$prev_t" in ''|*[!0-9]*) prev_t=$now ;; esac

mail(){ # mail SUBJECT BODY — ASCII subject on purpose: one plain header, nothing to encode
  local subj=$1 body=$2 f
  [ -n "$TEST_HEIGHT" ] && { subj="[TEST - simulated height] $subj"; body="THIS IS A TEST: TEST_HEIGHT=$TEST_HEIGHT was set, no real RPC was read.

$body"; }
  if [ "$DRY_RUN" = "1" ]; then printf '%s\n' "--- DRY_RUN mail to ${ALERT_RCPT:-<unset>}" "Subject: $subj" "" "$body" "---"; return 0; fi
  [ -z "$ALERT_RCPT" ] && { log "ALERT_RCPT is not set — mail NOT sent: $subj"; return 1; }
  [ -r "$SMTP_ENV" ] || { log "no $SMTP_ENV — mail NOT sent: $subj"; return 1; }
  # shellcheck disable=SC1090
  ( . "$SMTP_ENV"
    f=$(mktemp); trap 'rm -f "$f"' EXIT
    { echo "From: GembaChain halt check <$SMTP_USER>"; echo "To: $ALERT_RCPT"; echo "Subject: $subj"
      echo "Date: $(date -R)"; echo "Message-ID: <$(date +%s).$$@$WHO>"; echo "Content-Type: text/plain; charset=UTF-8"
      echo; printf '%s\n' "$body"; } >"$f"
    curl -s --max-time 30 --url "smtp://${SMTP_HOST}:${SMTP_PORT:-587}" --ssl-reqd --mail-from "$SMTP_USER" \
         --mail-rcpt "$ALERT_RCPT" --user "${SMTP_USER}:${SMTP_PASS}" --upload-file "$f" ) \
    && log "mail sent to $ALERT_RCPT: $subj" || { log "MAIL FAILED: $subj"; return 1; }
}

if [ "$best" -gt "$prev_h" ]; then
  echo "$best $now" >"$STATE"
  if [ -f "$MARK" ]; then
    read -r stuck since <"$MARK"
    mail "[GembaChain] RECOVERED - blocks again at height $best" \
"The chain is producing blocks again.

Height now:     $best
Was stuck at:   ${stuck:-?} (alert raised at $(date -u -d "@${since:-$now}" +'%F %H:%M UTC'))
Sources:       $seen
Checked from:   $WHO" && rm -f "$MARK"
  fi
  exit 0
fi

still=$((now - prev_t))
if [ "$still" -lt "$HALT_AFTER_SEC" ]; then
  [ "$still" -ge 60 ] && log "height $best unchanged for ${still}s (threshold ${HALT_AFTER_SEC}s) —$seen"
  exit 0
fi
[ -f "$MARK" ] && exit 1                 # already reported this episode
mail "[GembaChain] CHAIN HALTED at height $best - no new block for $((still/60)) min" \
"No source has seen a new block for ${still} s (threshold ${HALT_AFTER_SEC} s).

Height stuck at: $best (unchanged since $(date -u -d "@$prev_t" +'%F %H:%M:%S UTC'))
Sources:        $seen
Checked from:    $WHO

Four validators of near-equal weight tolerate ONE outage; two down stops consensus.
First look: which validators are down (Contabo maintenance shows as Cloudflare 521/522 on the RPCs),
then docs/runbooks/halt-recovery.md." && echo "$best $now" >"$MARK"
log "CHAIN HALTED — height $best for ${still}s —$seen"
exit 1
