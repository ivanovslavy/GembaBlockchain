#!/usr/bin/env bash
# gemba-chain-watch.sh — does the CHAIN still produce blocks?
#
# WHY THIS EXISTS. gemba-auto-unjail.sh watches THIS node. Nothing watched the chain itself, so a
# halted chain was silent: the per-box watchdogs each see their own node "fine but not advancing",
# the wallet listeners just read no new blocks, and silence raises no alarm. With four validators of
# near-equal weight the set tolerates exactly ONE outage — any two down and consensus stops. On
# 2026-10-18/19 Contabo rebooted three of them within 20 hours; only their staggering saved us.
#
# HOW IT AVOIDS FALSE ALARMS — two rules that matter:
#   1. The height is the MAX of this node and the public RPCs. A locally stuck node therefore does
#      NOT raise a chain alarm (that is the other watchdog's job); only a chain that stops for
#      everyone does.
#   2. No answer is NOT a halt. If every source fails to reply, this box has a network problem —
#      it logs and exits silently rather than crying wolf.
#
# It runs from the SAME 5-minute timer as the unjail watchdog, on EVERY validator box, so two boxes
# can be down and the third still reports. Three emails for one halt is deliberate: a halted chain
# is the loudest event there is.
set -uo pipefail
ENV_FILE=${ENV_FILE:-/etc/gemba/validator-auto.env}
[ -r "$ENV_FILE" ] && . "$ENV_FILE"

RPC=${RPC_HTTP:-http://localhost:26657}
LOG=${LOG_FILE:-/var/log/gemba-validator-auto.log}
TIPS=${TIP_EVM_RPCS:-}
NOTIFY_CMD=${NOTIFY_CMD:-}
HALT_AFTER_SEC=${HALT_AFTER_SEC:-240}          # no new block for this long (across ALL sources) => halted
STATE=${CHAIN_WATCH_STATE:-/var/lib/gemba/chain-watch.state}
MARK=${CHAIN_WATCH_MARK:-/var/lib/gemba/chain-watch.halted}

log(){ echo "[$(date -Is)] chain-watch: $*" >>"$LOG"; }
notify(){ [ -n "$NOTIFY_CMD" ] && $NOTIFY_CMD "gemba-chain: $*" >/dev/null 2>&1 || true; }
mkdir -p "$(dirname "$STATE")" 2>/dev/null

# --- highest block height any source will admit to -------------------------------------------------
best=0; srcs=0
h=$(curl -s --max-time 8 "$RPC/status" 2>/dev/null | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null)
case "$h" in ''|*[!0-9]*) : ;; *) srcs=$((srcs+1)); [ "$h" -gt "$best" ] && best=$h ;; esac
for u in $TIPS; do
  x=$(curl -s --max-time 8 -X POST -H 'content-type: application/json' \
      --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' "$u" 2>/dev/null \
      | jq -r '.result // empty' 2>/dev/null)
  [ -z "$x" ] && continue
  d=$((16#${x#0x})) 2>/dev/null || continue
  srcs=$((srcs+1)); [ "$d" -gt "$best" ] && best=$d
done

# RULE 2: nobody answered => this box is isolated, not the chain. Say nothing.
if [ "$srcs" -eq 0 ]; then log "no source answered ($((1+$(echo $TIPS|wc -w))) tried) — this box looks isolated; NOT treating as a halt"; exit 0; fi

now=$(date +%s)
prev_h=0; prev_t=$now
[ -r "$STATE" ] && { prev_h=$(cut -d' ' -f1 "$STATE" 2>/dev/null); prev_t=$(cut -d' ' -f2 "$STATE" 2>/dev/null); }
case "$prev_h" in ''|*[!0-9]*) prev_h=0 ;; esac
case "$prev_t" in ''|*[!0-9]*) prev_t=$now ;; esac

if [ "$best" -gt "$prev_h" ]; then
  echo "$best $now" > "$STATE"
  if [ -f "$MARK" ]; then
    stopped=$(cat "$MARK" 2>/dev/null)
    notify "RECOVERED — blocks are being produced again (height $best, was stuck at ${stopped:-?})"
    log "recovered — height moving again at $best"
    rm -f "$MARK"
  fi
  exit 0
fi

# Height did not move. How long has it been standing still?
still=$((now - prev_t))
[ "$still" -lt "$HALT_AFTER_SEC" ] && { log "height $best unchanged for ${still}s (threshold ${HALT_AFTER_SEC}s) — watching"; exit 0; }
[ -f "$MARK" ] && exit 0          # already reported this episode; stay quiet

# --- who is still signing, so the mail says WHY -----------------------------------------------------
sig=$(curl -s --max-time 8 "$RPC/block" 2>/dev/null \
      | jq -r '[.result.block.last_commit.signatures[] | select(.block_id_flag != 1 and .block_id_flag != "BLOCK_ID_FLAG_ABSENT")] | length' 2>/dev/null)
tot=$(curl -s --max-time 8 "$RPC/validators" 2>/dev/null | jq -r '.result.total // empty' 2>/dev/null)
echo "$best" > "$MARK"
log "🔴 CHAIN HALTED — height $best for ${still}s · signatures ${sig:-?}/${tot:-?}"
notify "🔴 CHAIN HALTED — no new block for $((still/60)) min. Height stuck at $best. Signatures on the last block: ${sig:-?} of ${tot:-?}. Four validators tolerate ONE outage; two down stops consensus. Check which validators are off."
