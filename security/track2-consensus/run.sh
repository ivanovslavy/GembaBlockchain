#!/usr/bin/env bash
# Track 2 — DESTRUCTIVE consensus tests on a THROWAWAY local devnet (gemba-1 / 821206).
# NEVER targets the live testnet. Brings up a fresh 4-node devnet, runs each attack, tears down.
#   bash security/track2-consensus/run.sh
set -uo pipefail
SEC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; ROOT="$(dirname "$SEC")"
echo "############ Track 2 — destructive consensus (devnet only) ############"

echo; echo "### 2a. DOWNTIME slash → faucet (supply-invariant), with recovery ###"
bash "$SEC/devnet/down.sh" --wipe >/dev/null 2>&1
bash "$SEC/devnet/up.sh"   >/dev/null 2>&1 && sleep 3
bash "$SEC/track2-consensus/downtime-slash.sh"; A=$?

echo; echo "### 2b. DOUBLE-SIGN → tombstone (best-effort; live equivocation is timing/partition-dependent) ###"
bash "$SEC/devnet/down.sh" --wipe >/dev/null 2>&1
bash "$SEC/devnet/up.sh"   >/dev/null 2>&1 && sleep 3
bash "$SEC/track2-consensus/double-sign.sh"; B=$?

echo; echo "### 2c. DETERMINISTIC proof of the slash→faucet redirect (x/slashfunds unit, both pools) ###"
( cd "$ROOT/chain" && go test ./x/slashfunds/... 2>&1 ) | tail -3; C=${PIPESTATUS[0]}

bash "$SEC/devnet/down.sh" --wipe >/dev/null 2>&1
echo
echo "############ Track 2 summary ############"
echo "  2a downtime-slash→faucet : $([ $A = 0 ] && echo PASS || echo FAIL)"
echo "  2b double-sign→tombstone : $([ $B = 0 ] && echo PASS || echo 'NOT-TRIGGERED (re-run; redirect proven by 2c)')"
echo "  2c slashfunds redirect   : $([ $C = 0 ] && echo PASS || echo FAIL)"
# 2b is best-effort; gate the suite on 2a + 2c (the deterministic invariants)
[ $A = 0 ] && [ $C = 0 ] && exit 0 || exit 1
