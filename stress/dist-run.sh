#!/usr/bin/env bash
# =============================================================================
# dist-run.sh — orchestrate the DISTRIBUTED load / rate-limit test from 4 IPs.
#
# Runs from your laptop/dev box. SSHes to the 4 load boxes (.82/.83/.84 + home .100)
# and drives load from ALL of them AT ONCE against the PUBLIC RPCs over the internet
# (rpc1/rpc2/rpc3) — never localhost. Each box is a distinct source IP, so this
# exercises Cloudflare + the per-IP nginx rate-limit exactly like real-world traffic.
#
#   *** The per-box setup already exists and persists (see docs/runbooks/
#       distributed-load-test.md). You normally just `fund` (if dust) then `flood`
#       or `harness`. Nothing to re-provision. ***
#
# NEVER point load at .162 or .137 — those are PRODUCTION. Targets = public RPCs only.
#
# Usage:
#   ./dist-run.sh status                 # what's running on each box
#   ./dist-run.sh fund                   # founder funds all 300 wallets (run from dev box; needs stress/.env FUNDER_PK=founder)
#   ./dist-run.sh flood [DUR] [CONC]     # rate-limit flood from 4 IPs (default 60s, conc 150) — proves the protection
#   ./dist-run.sh harness [A|B|C]        # full tx workload from 4 IPs (realistic load)
#   ./dist-run.sh monitor [SECS]         # poll chain health (height/mempool/bonded/supply)
#   ./dist-run.sh stop                   # kill any flood/harness on all 4 boxes
# =============================================================================
set -uo pipefail
BOXES=(13.140.139.82 13.140.139.83 13.140.139.84 88.203.191.208)   # 4 distinct source IPs
MONITOR_NODE=13.140.139.84      # any validator: read its local CometBFT (:26657) for chain health
SSH="ssh -o BatchMode=yes -o ConnectTimeout=8"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmd="${1:-status}"; shift || true

chain_health() { # one-line chain snapshot via a validator's local RPC (read-only, not load)
  timeout 8 $SSH slavy@$MONITOR_NODE 'S=$(curl -s --max-time 4 http://localhost:26657/status);
    printf "h=%s cu=%s mem=%s\n" \
      "$(echo "$S"|grep -oE "\"latest_block_height\":\"[0-9]+\""|grep -oE "[0-9]+")" \
      "$(echo "$S"|grep -oE "\"catching_up\":(true|false)"|head -1)" \
      "$(curl -s --max-time 3 http://localhost:26657/num_unconfirmed_txs|grep -oE "\"total\":\"[0-9]+\""|head -1)"' 2>/dev/null
}

case "$cmd" in
  status)
    for ip in "${BOXES[@]}"; do
      printf "  %-16s " "$ip"
      timeout 12 $SSH slavy@$ip 'echo "run.js=$(pgrep -fc "node scripts/run.js" 2>/dev/null||echo 0) flood=$(pgrep -fc "flood.mjs" 2>/dev/null||echo 0) node=$(node -v)"' 2>/dev/null
    done
    echo "  chain: $(chain_health)" ;;

  fund)   # founder disperses gas to all 300 wallets — run on the dev box with stress/.env FUNDER_PK=founder
    cd "$HERE" && node scripts/02-fund-wallets.js ;;

  flood)
    DUR="${1:-60}"; CONC="${2:-150}"
    echo ">> distributed flood: ${#BOXES[@]} IPs x conc $CONC x ${DUR}s -> public rpc1/2/3"
    tmp=$(mktemp -d)
    for ip in "${BOXES[@]}"; do $SSH slavy@$ip "node /home/slavy/flood.mjs $DUR $CONC" >"$tmp/$ip" 2>&1 & done
    end=$((SECONDS+DUR)); while [ $SECONDS -lt $end ]; do sleep 8; echo "  [$((end-SECONDS))s left] $(chain_health)"; done
    wait
    echo "── per-IP results ──"; for ip in "${BOXES[@]}"; do printf "  %-16s " "$ip"; cat "$tmp/$ip"; done
    echo "  post: $(chain_health)"; rm -rf "$tmp" ;;

  harness)
    P="${1:-A}"
    echo ">> distributed harness profile $P on ${#BOXES[@]} IPs -> public rpc1/2/3"
    for ip in "${BOXES[@]}"; do
      timeout 15 $SSH slavy@$ip "cd /home/slavy/stress && setsid nohup node scripts/run.js --profile=$P </dev/null >logs/run-$P.out 2>&1 & disown; exit 0" 2>/dev/null
    done
    echo "  launched; use './dist-run.sh monitor' to watch, './dist-run.sh stop' to end" ;;

  monitor)
    SECS="${1:-120}"; end=$((SECONDS+SECS))
    while [ $SECONDS -lt $end ]; do echo "  $(date -u +%H:%M:%S) $(chain_health)"; sleep 10; done ;;

  stop)
    for ip in "${BOXES[@]}"; do $SSH slavy@$ip 'pkill -9 -f "node scripts/run.js" 2>/dev/null; pkill -9 -f "flood.mjs" 2>/dev/null; echo "  '"$ip"' stopped"' 2>/dev/null; done ;;

  *) echo "usage: $0 {status|fund|flood [DUR CONC]|harness [A|B|C]|monitor [SECS]|stop}"; exit 1 ;;
esac
