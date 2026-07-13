#!/usr/bin/env bash
# =============================================================================
# run-72h-5x.sh — 72-HOUR endurance run at 5X the load of run-72h.sh.
# A copy of run-72h.sh that changes ONLY the load + funding and touches nothing
# else (weights, contracts, fees-per-gas, RPCs, wallet count all stay as .env):
#
#     TARGET_TPS           4  ->  20    (5x steady throughput  -> ~5.2M tx / 72h)
#     CONCURRENCY          20 -> 100    (5x max parallel in-flight submits)
#     RECEIPT_CONCURRENCY  6  ->  24    (keep receipt scan ahead of 5x mined txs)
#     FUND_PER_WALLET      30 -> 100    (5x gas is ~31 GMB expected / <=67 worst-
#                                        case; 100 covers worst-case + working
#                                        capital for native ops + headroom)
#     STEADY_SEC       259200 (72h, same as run-72h.sh)
#
# dotenv does NOT override already-set env vars, so everything else still comes
# from .env unchanged. The prior run's auto-cleanup drained the worker wallets,
# so we (re)seed them first (top-up to 100 GMB each + mint tokens + approvals,
# founder pays), then launch fully detached.
#
# Usage (on the Pi):  ./run-72h-5x.sh
# Monitor:            tail -f logs/endurance-72h-5x.out
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

export STEADY_SEC=259200          # 72h steady phase
export TARGET_TPS=20              # 5x steady rate (was 4)
export CONCURRENCY=100            # 5x max parallel in-flight (was 20)
export RECEIPT_CONCURRENCY=24     # 4x receipt workers (was 6) to drain 5x receipts
export FUND_PER_WALLET=100        # 5x-safe funding (was 30)

echo "=== $(date -u) 5X 72h: (re)seed ${WALLET_COUNT:-100} wallets to ${FUND_PER_WALLET} GMB each (founder pays) ==="
node scripts/02-seed-wallets.mjs

echo "=== $(date -u) launch detached 5X 72h run (TPS=${TARGET_TPS}, C=${CONCURRENCY}) -> logs/endurance-72h-5x.out ==="
setsid nohup node scripts/run.js --profile=ENDURANCE > logs/endurance-72h-5x.out 2>&1 < /dev/null &
echo $! > endurance-72h-5x.pid
sleep 1
echo "launched pid $(cat endurance-72h-5x.pid) | 5X 72h run | log: logs/endurance-72h-5x.out"
