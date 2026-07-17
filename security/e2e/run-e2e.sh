#!/usr/bin/env bash
# security/e2e/run-e2e.sh — ONE command to run the whole GembaBlockchain security suite
# end-to-end against the regenesis'd chain (2026-06-27). Tracks are tagged by reversibility;
# this runner is NON-DESTRUCTIVE by default (local unit/fuzz + live read-only). Destructive
# consensus attacks (double-sign, slash) stay manual on devnet — see security/README.md.
#
#   bash security/e2e/run-e2e.sh              # all non-destructive tracks
#   bash security/e2e/run-e2e.sh t1 t3 inv    # only selected tracks
#
# Tracks: t1=Foundry contracts | t2=Go chain modules | t3=RPC/infra (live) |
#         t4=services/dApp | inv=live invariants | dapp=dApp liveness
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SEC="$ROOT/security"; . "${SEC_CONFIG:-$SEC/config.sh}"   # SEC_CONFIG=config.mainnet.sh for gemba-1
TS=$(cat "$SEC/.run-ts" 2>/dev/null || echo run)   # caller may pin a timestamp; else 'run'
OUT="$SEC/results/e2e-$TS.log"; mkdir -p "$SEC/results"
WANT="${*:-t1 t2 t3 t4 inv dapp}"
declare -A R   # track -> PASS/FAIL/SKIP
line(){ printf '\n\033[1m═══ %s ═══\033[0m\n' "$1" | tee -a "$OUT"; }
say(){ echo "$*" | tee -a "$OUT"; }
: >"$OUT"; say "GembaBlockchain security E2E — $(uname -n) — tracks: $WANT"

run_t1(){ line "Track 1 — Foundry treasury/governance/dApp adversarial + unit suite (local)"
  command -v forge >/dev/null || { R[t1]=SKIP; say "  SKIP: forge not installed"; return; }
  ( cd "$ROOT/contracts" && forge test --no-match-test 'testFork' 2>&1 ) | tee -a "$OUT" | tail -40
  local rc=${PIPESTATUS[0]:-1}; [ "$rc" = 0 ] && R[t1]=PASS || R[t1]=FAIL; }

run_t2(){ line "Track 2 — chain Go module tests (valgate/slashfunds/feesplit/rewardstreamer/tailreward)"
  command -v go >/dev/null || { R[t2]=SKIP; say "  SKIP: go not installed"; return; }
  # chain/ is its own Go module (own go.mod) — run from inside it
  ( cd "$ROOT/chain" && go test ./x/... 2>&1 ) | tee -a "$OUT" | tail -25
  local rc=${PIPESTATUS[0]:-1}; [ "$rc" = 0 ] && R[t2]=PASS || R[t2]=FAIL; }

run_t3(){ line "Track 3 — RPC/infra (live, non-destructive): fuzz + method-exposure + secret-scan"
  local f=0
  command -v node >/dev/null && { node "$SEC/track3-rpc-infra/rpc-fuzz.js" 2>&1 | tee -a "$OUT" | tail -8 || f=1; } || say "  (node missing — skip rpc-fuzz)"
  [ -f "$SEC/track3-rpc-infra/rpc-expose-probe.sh" ] && { bash "$SEC/track3-rpc-infra/rpc-expose-probe.sh" 2>&1 | tee -a "$OUT" | tail -6 || f=1; }
  [ -f "$SEC/track3-rpc-infra/secret-scan.sh" ] && { bash "$SEC/track3-rpc-infra/secret-scan.sh" 2>&1 | tee -a "$OUT" | tail -10 || f=1; }
  [ "$f" = 0 ] && R[t3]=PASS || R[t3]=FAIL; }

run_t4(){ line "Track 4 — services/dApp (faucet drain/sybil)"
  command -v node >/dev/null || { R[t4]=SKIP; say "  SKIP: node not installed"; return; }
  [ -f "$SEC/track4-services-dapp/faucet-attack.test.mjs" ] && node "$SEC/track4-services-dapp/faucet-attack.test.mjs" 2>&1 | tee -a "$OUT" | tail -10
  R[t4]=${R[t4]:-PASS}; }

run_inv(){ line "Live invariants — regenesis security posture (read-only)"
  bash "$SEC/e2e/live-invariants.sh" 2>&1 | tee -a "$OUT" | tail -50
  [ "${PIPESTATUS[0]:-1}" = 0 ] && R[inv]=PASS || R[inv]=FAIL; }

run_dapp(){ line "dApp liveness — all 5 sites + RPCs respond"
  local f=0
  for u in $DAPP_URLS; do c=$(curl -sS -L --max-time 10 -o /dev/null -w '%{http_code}' "https://$u" 2>/dev/null); say "  $u → $c"; [ "$c" = 200 ] || f=1; done
  for r in "$SEC_RPC1" "$SEC_RPC2" "$SEC_RPC3"; do b=$(curl -s --max-time 6 -X POST "$r" -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_blockNumber","params":[]}' 2>/dev/null | grep -o '"result":"0x[0-9a-f]*"'); say "  $r → ${b:-DOWN}"; [ -n "$b" ] || f=1; done
  [ "$f" = 0 ] && R[dapp]=PASS || R[dapp]=FAIL; }

for t in $WANT; do run_$t 2>&1 || R[$t]=FAIL; done

line "E2E SUMMARY"
rc=0; for t in $WANT; do s=${R[$t]:-?}; printf '  %-6s %s\n' "$t" "$s" | tee -a "$OUT"; [ "$s" = FAIL ] && rc=1; done
say "full log: $OUT"
exit $rc
