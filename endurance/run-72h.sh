#!/usr/bin/env bash
# =============================================================================
# run-72h.sh — 72-HOUR endurance run. A copy of the standard 24h launch that
# changes ONLY two values and touches NOTHING else (the 24h setup — .env,
# run.js, profiles.js — stays exactly as it is):
#
#     STEADY_SEC        86400 (24h)  ->  259200 (72h)
#     FUND_PER_WALLET      15 GMB    ->      30 GMB   (2x per wallet)
#
# These are exported here; dotenv does NOT override already-set env vars, so the
# rest of the config (RPC_URLS, FUNDER_PK, WALLET_COUNT, fees, …) still comes
# from .env unchanged. To go back to 24h just run the normal command in README.
#
# The 24h run's auto-cleanup drained the worker wallets, so we (re)seed them
# first (top-up to 30 GMB each + mint tokens + approvals, founder pays), then
# launch the run fully detached.
#
# Usage (on the Pi):  ./run-72h.sh
# Monitor:            tail -f logs/endurance-72h.out
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

export STEADY_SEC=259200        # 72h steady phase (was 86400 = 24h)
export FUND_PER_WALLET=30       # 2x GMB per wallet (was 15)

echo "=== $(date -u) 72h endurance: (re)seed 100 wallets to ${FUND_PER_WALLET} GMB each (founder pays) ==="
node scripts/02-seed-wallets.mjs

echo "=== $(date -u) launch detached 72h run (STEADY_SEC=${STEADY_SEC}) -> logs/endurance-72h.out ==="
setsid nohup node scripts/run.js --profile=ENDURANCE > logs/endurance-72h.out 2>&1 < /dev/null &
echo $! > endurance-72h.pid
sleep 1
echo "launched pid $(cat endurance-72h.pid) | 72h run | log: logs/endurance-72h.out"
