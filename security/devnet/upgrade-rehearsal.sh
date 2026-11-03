#!/usr/bin/env bash
# =============================================================================
# upgrade-rehearsal.sh — run the coordinated halt-height upgrade END TO END on a throwaway local
# 4-validator devnet, exactly as docs/runbooks/validator-binary-refresh-2026-10.md prescribes for
# the live chain, and measure it.
#
#   OLD=/path/to/gembad-39daa6e NEW=/path/to/gembad-candidate ./security/devnet/upgrade-rehearsal.sh
#
# DEVNET ONLY: chain-id gemba-1 / EVM 821206 on localhost (security/devnet/up.sh). It never talks to
# the live testnet. The validators run from ONE file, $BASE/bin/gembad, the way every live box runs
# /usr/local/bin/gembad — so "swap the binary" here is the same `cp` as there.
#
# Phases (each prints PASS/FAIL with the raw value):
#   0  boot the devnet on OLD
#   1  baseline on OLD: the §6 defect (a failing delegation burns the day's allowance) and the
#      BLOBBASEFEE defect (eth_call nil-pointer; a tx is included as a Cosmos-level panic, code 111222)
#   2  set halt-height H on every node, ONE AT A TIME, never two validators down at once
#   3  the chain halts at H by itself; measure
#   4  swap to NEW, clear halt-height, start node by node; measure the halt (block time H-1 → H)
#   5  verify on NEW: same app hash on all four, nobody jailed, no panics, the failing delegation
#      leaves the §6 counter untouched, BLOBBASEFEE answers 0 in eth_call and in a transaction,
#      and the Prague suite
#   6  (DIVERGENCE_TEST=1, default on) prove the BLOBBASEFEE patch is state-machine-breaking: put
#      ONE node back on OLD and send a BLOBBASEFEE transaction — that node must stop on an app-hash
#      mismatch while the other three carry on
# Exit code = number of FAILs.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OLD=${OLD:?set OLD=<old gembad binary>}; NEW=${NEW:?set NEW=<new gembad binary>}
BASE=${BASE:-$HOME/.gembad-rehearsal}
HALT_OFFSET=${HALT_OFFSET:-40}          # blocks between "pick H" and H — enough for 4 sequential restarts
DIVERGENCE_TEST=${DIVERGENCE_TEST:-1}
. "$ROOT/chain/scripts/gemba.params.sh"
N=4; FAILS=0; BIN="$BASE/bin/gembad"; KR=(--keyring-backend test)
pass(){ echo "PASS  $*"; }; fail(){ echo "FAIL  $*"; FAILS=$((FAILS+1)); }; info(){ echo "INFO  $*"; }
step(){ echo; echo "=== $* ==="; }
rpcp(){ echo $((26657+$1*100)); }
st(){ curl -s --max-time 3 "localhost:$(rpcp "$1")/status" 2>/dev/null; }
height(){ st "$1" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null; }
pid_of(){ local p; for p in $(pgrep -x gembad); do tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | grep -q -- "--home $BASE/node$1 " && echo "$p"; done; }
start_node(){
  local i=$1
  nohup "$BIN" start --home "$BASE/node$i" --chain-id "$COSMOS_CHAIN_ID" --evm.evm-chain-id "$EVM_CHAIN_ID" \
    --minimum-gas-prices "$MIN_GAS_PRICES_NODE" --rpc.laddr "tcp://127.0.0.1:$(rpcp "$i")" \
    --json-rpc.enable=true --json-rpc.address "127.0.0.1:$((8545+i*100))" >>"$BASE/node$i.log" 2>&1 &
}
stop_node(){ local p; p=$(pid_of "$1"); [ -n "$p" ] && kill $p; for _ in $(seq 1 40); do [ -z "$(pid_of "$1")" ] && return 0; sleep 0.5; done; kill -9 $p 2>/dev/null; }
wait_height(){ local i=$1 want=$2 t; for t in $(seq 1 ${3:-120}); do h=$(height "$i"); [ -n "$h" ] && [ "$h" -ge "$want" ] && return 0; sleep 1; done; return 1; }
set_halt(){ sed -i "s/^halt-height = .*/halt-height = $2/" "$BASE/node$1/config/app.toml"; }
blocktime(){ curl -s "localhost:$(rpcp 0)/block?height=$1" | jq -r .result.block.header.time; }
apphash(){ curl -s "localhost:$(rpcp "$1")/block?height=$2" | jq -r .result.block.header.app_hash; }
epoch(){ date -d "$1" +%s.%N; }
G(){ "$BIN" "$@"; }
valhex(){ G debug addr "$(G keys show "val$1" -a "${KR[@]}" --home "$BASE/node$1")" 2>&1 | awk '/Address hex/{print $3}' | sed 's/^0x//' | tr 'A-F' 'a-f'; }
# §6 record of validator i straight from the committed store: 8-byte BE day ++ the amount as ASCII.
counter(){
  local v; v=$(curl -s "localhost:$(rpcp 0)/abci_query?path=%22/store/valgate/key%22&data=0x02$(valhex "$1")" | jq -r '.result.response.value // empty')
  [ -z "$v" ] && { echo "NO RECORD"; return; }
  echo "$v" | base64 -d | python3 -c 'import sys;b=sys.stdin.buffer.read();print("day %d · %s agmb"%(int.from_bytes(b[:8],"big"),b[8:].decode()))'
}
delegate(){ # delegate(i, amount_agmb) from val i's own key to its own validator; prints "submit=<code> block=<code> <log>"
  local i=$1 amt=$2 vo out hash r
  vo=$(G keys show "val$i" --bech val -a "${KR[@]}" --home "$BASE/node$i")
  out=$(G tx staking delegate "$vo" "${amt}agmb" --from "val$i" "${KR[@]}" --home "$BASE/node$i" --chain-id "$COSMOS_CHAIN_ID" \
        --node "tcp://localhost:$(rpcp "$i")" --gas 300000 --gas-prices "$MIN_GAS_PRICES_NODE" -y -o json 2>&1)
  hash=$(echo "$out" | jq -r '.txhash // empty' 2>/dev/null)
  [ -z "$hash" ] && { echo "submit=ERR $(echo "$out" | tail -1 | cut -c1-160)"; return; }
  for _ in $(seq 1 30); do r=$(G q tx "$hash" --node "tcp://localhost:$(rpcp "$i")" -o json 2>/dev/null) && break; sleep 1; done
  echo "submit=$(echo "$out" | jq -r .code) block=$(echo "$r" | jq -r .code) $(echo "$r" | jq -r .raw_log | cut -c1-120)"
}
# panic / consensus-failure lines logged by node i AFTER the swap (the deliberate halt itself may log
# a consensus failure on OLD; that is the halt, not a fault). Match the real markers, not the word
# "panic" — gembad's own --help lists it as a log level (see the runbook's trap list).
declare -a LOGMARK=(0 0 0 0)
panics(){ tail -n +"$(( ${LOGMARK[$1]} + 1 ))" "$BASE/node$1.log" | sed 's/\x1b\[[0-9;]*m//g' | grep -c -E '^panic:|SIGSEGV|CONSENSUS FAILURE|wrong Block.Header.AppHash' ; }

mkdir -p "$BASE.bin.tmp"
# ---------------------------------------------------------------------------------------------------
step "0  boot a 4-validator devnet on OLD ($("$OLD" version 2>&1 | head -1)) · sha256 $(sha256sum "$OLD" | cut -c1-16)…"
for p in $(pgrep -x gembad); do tr '\0' ' ' </proc/$p/cmdline | grep -q -- "--home $BASE/" && kill $p; done; sleep 2
rm -rf "$BASE" "$BASE".init.log; mkdir -p "$(dirname "$BIN")"
# up.sh wipes and initialises $BASE, so build it first and only then plant the binary inside it.
EVMD="$OLD" BASE="$BASE" bash "$ROOT/security/devnet/up.sh" >/dev/null 2>&1 || { echo "up.sh failed"; exit 1; }
for p in $(pgrep -x "$(basename "$OLD" | cut -c1-15)"); do tr '\0' ' ' </proc/$p/cmdline | grep -q -- "--home $BASE/" && kill $p; done; sleep 3
mkdir -p "$(dirname "$BIN")"; cp "$OLD" "$BIN"
for i in 0 1 2 3; do start_node $i; done
wait_height 0 5 90 && pass "OLD devnet producing (height $(height 0)), version $("$BIN" version 2>&1 | head -1)" || { fail "devnet did not start"; exit 1; }

# ---------------------------------------------------------------------------------------------------
step "1  baseline on OLD"
info "§6 val1 before: $(counter 1)"
r=$(delegate 1 50000000000000000000); info "val1 delegates 50 GMB with <1 GMB liquid → $r"
c=$(counter 1); case "$c" in *"50000000000000000000 agmb") info "§6 val1 after the FAILED delegation: $c  ← the defect: a delegation that never happened burned the day";; *) info "§6 val1 after: $c";; esac
r=$(curl -s -X POST -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[{"data":"0x4a5f5260205ff3"},"latest"]}' localhost:8545 | jq -c '.result // .error.message')
info "BLOBBASEFEE eth_call on OLD → $r"

# ---------------------------------------------------------------------------------------------------
step "2  set halt-height on every node, one at a time"
H=$(( $(height 0) + HALT_OFFSET )); info "halt-height H = $H (now $(height 0), +$HALT_OFFSET blocks ≈ $((HALT_OFFSET*23/10)) s at 2.3 s)"
for i in 0 1 2 3; do
  set_halt $i $H; stop_node $i; start_node $i
  before=$(height $(( (i+1)%N ))); wait_height $i $((before+2)) 60 && info "node$i restarted with halt-height=$H, back at $(height $i)" || fail "node$i did not come back"
  [ "$(height 0)" -ge "$H" ] && { fail "reached H before every node was armed — raise HALT_OFFSET"; break; }
done

# ---------------------------------------------------------------------------------------------------
step "3  wait for the halt at H"
# Poll every node; remember the highest block anyone committed and its timestamp WHILE the nodes
# still answer (a halted node may exit). Halted = no node's height moved for 15 s.
maxh=0; T_LAST=""; still=0
for t in $(seq 1 400); do
  moved=0
  for i in 0 1 2 3; do h=$(height $i); if [ -n "$h" ] && [ "$h" -gt "$maxh" ]; then maxh=$h; moved=1; T_LAST=$(curl -s "localhost:$(rpcp $i)/block?height=$h" | jq -r .result.block.header.time); fi; done
  [ "$moved" = 1 ] && still=0 || still=$((still+1))
  [ "$maxh" -ge $((H-1)) ] && [ "$still" -ge 15 ] && break
  sleep 1
done
W_HALT=$(date +%s.%N); LASTH=$maxh
hs=$(for i in 0 1 2 3; do h=$(height $i); echo -n "${h:-down} "; done)
alive=0; for i in 0 1 2 3; do [ -n "$(pid_of $i)" ] && alive=$((alive+1)); done
info "heights after the halt: $hs· gembad processes still running: $alive/4 (a halted node does NOT exit — it idles with consensus stopped)"
[ "$maxh" -le "$H" ] && [ "$maxh" -ge $((H-1)) ] && pass "chain stopped by itself — last committed block $maxh at $T_LAST (H=$H)" || fail "halt at the wrong height: $maxh (H=$H)"
for i in 0 1 2 3; do sed 's/\x1b\[[0-9;]*m//g' "$BASE/node$i.log" | grep -i -m1 "halt" | cut -c1-160 | sed "s/^/      node$i: /"; done

# ---------------------------------------------------------------------------------------------------
step "4  swap OLD → NEW, clear halt-height, start node by node"
for i in 0 1 2 3; do stop_node $i; done
for i in 0 1 2 3; do LOGMARK[$i]=$(wc -l <"$BASE/node$i.log"); done
cp "$NEW" "$BIN"; info "binary now $("$BIN" version 2>&1 | head -1) · sha256 $(sha256sum "$BIN" | cut -c1-16)…"
W_SWAP=$(date +%s.%N)
for i in 0 1 2 3; do set_halt $i 0; start_node $i; done
# Block H was COMMITTED by CometBFT before FinalizeBlock refused it, so the NEW binary executes
# block H on restart. Block H+1's header time is the median of the precommits for H — cast BEFORE
# the halt — so it does not show the stall; block H+2's time (precommits for H+1, cast after the
# restart) does. Stall = time(H+2) − time(H+1).
wait_height 0 $((LASTH+2)) 180 && W_RESUME=$(date +%s.%N) || { fail "chain did not resume"; W_RESUME=""; }
if [ -n "$W_RESUME" ]; then
  T1=$(blocktime $((LASTH+1))); T2=$(blocktime $((LASTH+2)))
  d=$(python3 -c "print(round($(epoch "$T2")-$(epoch "$T1"),1))")
  pass "chain resumed on NEW: block $((LASTH+1)) at $T1, block $((LASTH+2)) at $T2 — chain stalled ${d} s in total"
  info "operator part of that stall here: halt detected (after 15 s of stillness) → swap → +2 blocks = $(python3 -c "print(round($W_RESUME-$W_HALT,1))") s; restart → +2 blocks = $(python3 -c "print(round($W_RESUME-$W_SWAP,1))") s"
fi

# ---------------------------------------------------------------------------------------------------
step "5  verify on NEW"
wait_height 0 $((LASTH+8)) 60
for i in 0 1 2 3; do v=$(curl -s "localhost:$((8545+i*100))" -X POST -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"web3_clientVersion","params":[]}' | jq -r .result | head -1); info "node$i: $v · height $(height $i)"; done
X=$((LASTH+5)); hs=$(for i in 0 1 2 3; do apphash $i $X; done | sort -u | wc -l)
[ "$hs" -eq 1 ] && pass "same app hash on all four nodes at $X ($(apphash 0 $X | cut -c1-16)…)" || fail "app hashes differ at $X"
j=$(G q staking validators --node "tcp://localhost:$(rpcp 0)" -o json 2>/dev/null | jq '[.validators[] | select(.jailed==true)] | length')
[ "$j" = "0" ] && pass "no validator jailed (the halt costs no missed-block penalty)" || fail "$j validator(s) jailed"
p=0; for i in 0 1 2 3; do p=$((p+$(panics $i))); done; [ "$p" -eq 0 ] && pass "no panic / consensus failure in any node log" || fail "$p panic lines in the logs"
c0=$(counter 2); r=$(delegate 2 50000000000000000000); c1=$(counter 2)
info "val2 delegates 50 GMB with <1 GMB liquid → $r"
[ "$c0" = "$c1" ] && pass "§6: the FAILED delegation left val2's counter untouched ($c1)" || fail "§6 counter moved on a failed delegation: $c0 → $c1"
r=$(delegate 3 500000000000000000); c=$(counter 3)
case "$r" in *"block=0"*) case "$c" in *" 500000000000000000 agmb") pass "§6: a successful 0.5 GMB delegation is charged once ($c)";; *) fail "§6 after a successful delegation: $c";; esac;; *) fail "0.5 GMB delegation → $r";; esac
S="$BASE.bin.tmp"; G keys unsafe-export-eth-key founder "${KR[@]}" --home "$BASE/node0" 2>/dev/null >"$S/pk"; G keys unsafe-export-eth-key dao "${KR[@]}" --home "$BASE/node0" 2>/dev/null >"$S/pk2"; chmod 600 "$S"/pk*
RPC=http://127.0.0.1:8545 PK=$(cat "$S/pk") PK2=$(cat "$S/pk2") bash "$ROOT/security/devnet/evm-compat/prague-suite.sh" | sed 's/^/      /'
[ "${PIPESTATUS[0]}" -eq 0 ] && pass "prague-suite: 0 FAIL on NEW" || fail "prague-suite reported failures on NEW"

# ---------------------------------------------------------------------------------------------------
if [ "$DIVERGENCE_TEST" = "1" ]; then
  step "6  is the BLOBBASEFEE patch state-machine-breaking? one node back on OLD, then a BLOBBASEFEE tx"
  stop_node 3; cp "$OLD" "$S/gembad"; MARK3=$(wc -l <"$BASE/node3.log")
  nohup "$S/gembad" start --home "$BASE/node3" --chain-id "$COSMOS_CHAIN_ID" --evm.evm-chain-id "$EVM_CHAIN_ID" \
    --minimum-gas-prices "$MIN_GAS_PRICES_NODE" --rpc.laddr "tcp://127.0.0.1:$(rpcp 3)" --json-rpc.enable=false >>"$BASE/node3.log" 2>&1 &
  sleep 8; h3=$(height 3); info "node3 on OLD again, following at $h3 while 3 of 4 run NEW"
  out=$(cast send --rpc-url http://127.0.0.1:8545 --private-key "0x$(cat "$S/pk")" --gas-price 10000000000 --gas-limit 100000 --json --create 0x4a5f5500 2>&1)
  info "BLOBBASEFEE tx → status $(echo "$out" | jq -r '.status // "none"' 2>/dev/null) in block $(( $(echo "$out" | jq -r '.blockNumber // "0x0"' 2>/dev/null) ))"
  sleep 15
  a=$(height 0); b=$(height 3)
  mm=$(tail -n +"$((MARK3+1))" "$BASE/node3.log" | sed 's/\x1b\[[0-9;]*m//g' | grep -m1 -i -E "wrong Block.Header.AppHash|app.?hash mismatch|CONSENSUS FAILURE" | cut -c1-200)
  info "after the tx: NEW nodes at $a, OLD node3 at ${b:-down}"
  if [ -n "$mm" ] || { [ -n "$b" ] && [ $((a-b)) -gt 3 ]; }; then pass "OLD node3 left consensus on the BLOBBASEFEE tx — the patch IS state-machine-breaking: ${mm:-stuck at $b}"
  else fail "OLD node3 did not diverge (a=$a b=$b) — re-check the consensus classification"; fi
  for p in $(pgrep -x gembad); do tr '\0' ' ' </proc/$p/cmdline | grep -q -- "--home $BASE/node3 " && kill $p; done
fi

echo; echo "=== rehearsal done: $FAILS FAIL(s). Devnet left running at $BASE (stop: kill the gembad PIDs on --home $BASE/node*)."
rm -f "$S"/pk*
exit "$FAILS"
