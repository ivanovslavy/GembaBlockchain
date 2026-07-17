#!/usr/bin/env bash
# =============================================================================
# run-full-prevalidation.sh — the FULL security + e2e validation battery for the
# mainnet launch, in one orchestrator. PREPARED 2026-07-18 on the owner's order
# ("подготви, не пускай") — nothing runs unless you explicitly say `run`.
#
#   ./run-full-prevalidation.sh            # = plan: print what would run, run nothing
#   ./run-full-prevalidation.sh run        # run every LOCAL stage (1-4)
#   ./run-full-prevalidation.sh run static # run one stage by name
#
# Stages (logs land in security/results/prevalidation-<UTC-date>/):
#   1 static   — contracts `forge test` (full) + chain `go test -count=1 ./...`
#   2 build    — clean `build-gembad.sh` (pinned cosmos/evm + wiring patch incl. the
#                L1 begin-blocker assertion)
#   3 genesis  — throwaway mainnet-genesis ceremony dry-run: build → 33-assert verify
#                → 4 gentx → collect → boot a 4-node net → REQUIRE height > 0
#   4 fuzz     — JSON-RPC fuzz + method-exposure probe against $SEC_CONFIG endpoints
#                (testnet config until mainnet exists; rerun with config.mainnet.sh)
#   5 live     — e2e/run-e2e.sh + e2e/live-invariants.sh with
#                SEC_CONFIG=config.mainnet.sh — POST-LAUNCH ONLY (needs the live
#                chain + deployed contracts; ceremony runbook Phase 7). `run` skips
#                it unless you name it explicitly: `run live`.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
STAMP="$(date -u +%Y%m%d)"
OUT="$HERE/results/prevalidation-$STAMP"
GEMBAD_BIN="${GEMBAD:-/tmp/gembad}"

plan() {
  sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'
  echo "PLAN ONLY — nothing was executed. Say:  $0 run"
}

log() { printf '\n\033[1;36m==== %s ====\033[0m\n' "$*"; }
res() { [ "$1" -eq 0 ] && echo "STAGE RESULT: PASS" || echo "STAGE RESULT: FAIL (exit $1)"; }

stage_static() {
  log "1 static — forge test + go test"
  (cd "$ROOT/contracts" && forge test) 2>&1 | tee "$OUT/1-forge-test.log"; f=${PIPESTATUS[0]}
  (cd "$ROOT/chain" && go test -count=1 ./...) 2>&1 | tee "$OUT/1-go-test.log"; g=${PIPESTATUS[0]}
  res $((f + g)); return $((f + g))
}

stage_build() {
  log "2 build — clean build-gembad.sh"
  (cd "$ROOT/chain/gembad" && ./build-gembad.sh) 2>&1 | tee "$OUT/2-build.log"
  res "${PIPESTATUS[0]}"; return "${PIPESTATUS[0]}"
}

stage_genesis() {
  log "3 genesis — throwaway ceremony dry-run + 4-node boot"
  local W; W="$(mktemp -d)"
  (
    set -e
    cd "$W"
    for i in 0 1 2 3; do
      "$GEMBAD_BIN" init "dry-val$i" -o --chain-id gemba-1 --home "v$i" >/dev/null 2>&1
      "$GEMBAD_BIN" keys add val --keyring-backend test --algo eth_secp256k1 --home "v$i" >/dev/null 2>&1
    done
    "$GEMBAD_BIN" init dry-ops -o --chain-id gemba-1 --home ops >/dev/null 2>&1
    for k in founder foundation dao contingency publicfaucet; do
      "$GEMBAD_BIN" keys add "$k" --keyring-backend test --algo eth_secp256k1 --home ops >/dev/null 2>&1
    done
    A() { "$GEMBAD_BIN" keys show "$1" -a --keyring-backend test --home "$2"; }
    VALS="$(A val v0) $(A val v1) $(A val v2) $(A val v3)"
    OUT_DIR="$W/genesis-out" FOUNDER_ADDR="$(A founder ops)" FOUNDATION_ADDR="$(A foundation ops)" \
      DAO_ADDR="$(A dao ops)" CONTINGENCY_ADDR="$(A contingency ops)" \
      PUBLICFAUCET_ADDR="$(A publicfaucet ops)" VAL_ADDRS="$VALS" \
      OUT="$W/genesis-out" GEMBAD="$GEMBAD_BIN" \
      "$ROOT/chain/gembad/init-gembad-mainnet.sh" build
    mkdir -p gentxs
    for i in 0 1 2 3; do
      cp genesis-out/config/genesis.json "v$i/config/genesis.json"
      "$GEMBAD_BIN" genesis gentx val 10000000000000000000000agmb \
        --min-self-delegation 1000000000000000000000 --gas-prices 5000000000agmb \
        --keyring-backend test --chain-id gemba-1 --home "v$i" >/dev/null 2>&1
      cp "v$i"/config/gentx/*.json gentxs/
    done
    OUT="$W/genesis-out" GEMBAD="$GEMBAD_BIN" GENTX_DIR="$W/gentxs" \
      "$ROOT/chain/gembad/init-gembad-mainnet.sh" collect
    # boot the 4 nodes on port-shifted configs and demand real blocks
    declare -a IDS
    for i in 0 1 2 3; do IDS[$i]="$("$GEMBAD_BIN" comet show-node-id --home "v$i")"; done
    for i in 0 1 2 3; do
      C="v$i/config/config.toml"; APP="v$i/config/app.toml"
      P2P=$((26656+i*100)); RPC=$((26657+i*100)); PROX=$((26658+i*100)); GRPC=$((9090+i*10))
      sed -i "s|^type = \"flood\"|type = \"app\"|; s|^timeout_commit = .*|timeout_commit = \"1s\"|; s|tcp://127.0.0.1:26658|tcp://127.0.0.1:$PROX|; s|tcp://127.0.0.1:26657|tcp://127.0.0.1:$RPC|; s|tcp://0.0.0.0:26656|tcp://0.0.0.0:$P2P|; s|localhost:6060|localhost:$((6060+i))|; s|^addr_book_strict = true|addr_book_strict = false|; s|^allow_duplicate_ip = false|allow_duplicate_ip = true|" "$C"
      PEERS=""; for j in 0 1 2 3; do [ "$j" -eq "$i" ] && continue; PEERS="$PEERS,${IDS[$j]}@127.0.0.1:$((26656+j*100))"; done
      sed -i "s|^persistent_peers = .*|persistent_peers = \"${PEERS#,}\"|" "$C"
      sed -i "s|^minimum-gas-prices = .*|minimum-gas-prices = \"5000000000agmb\"|; s|^evm-chain-id = .*|evm-chain-id = 821206|; s|tcp://localhost:9090|tcp://localhost:$GRPC|" "$APP"
      "$GEMBAD_BIN" start --home "v$i" --chain-id gemba-1 --evm.evm-chain-id 821206 >"$W/v$i.log" 2>&1 &
    done
    sleep 30
    H="$(curl -s localhost:26657/status | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo 0)"
    pkill -f "gembad start --home $W" 2>/dev/null || true
    echo "boot height after 30s: ${H:-0}"
    [ "${H:-0}" -gt 0 ] || { echo "FAIL: no blocks produced"; grep -m3 -i 'err\|panic' "$W/v0.log"; exit 1; }
  ) 2>&1 | tee "$OUT/3-genesis-dryrun.log"
  local rc="${PIPESTATUS[0]}"
  rm -rf "$W"
  res "$rc"; return "$rc"
}

stage_fuzz() {
  log "4 fuzz — JSON-RPC fuzz + exposure probe (config: ${SEC_CONFIG:-security/config.sh})"
  ( cd "$HERE/track3-rpc-infra" && node rpc-fuzz.js ) 2>&1 | tee "$OUT/4-rpc-fuzz.log"; f=${PIPESTATUS[0]}
  ( cd "$HERE/track3-rpc-infra" && bash rpc-expose-probe.sh ) 2>&1 | tee "$OUT/4-rpc-expose.log"; g=${PIPESTATUS[0]}
  res $((f + g)); return $((f + g))
}

stage_live() {
  log "5 live — e2e + live-invariants (POST-LAUNCH; SEC_CONFIG=config.mainnet.sh)"
  echo "Requires the LIVE mainnet + filled security/config.mainnet.sh (ceremony Phase 7)."
  ( SEC_CONFIG="$HERE/config.mainnet.sh" bash "$HERE/e2e/run-e2e.sh" ) 2>&1 | tee "$OUT/5-e2e.log"
  res "${PIPESTATUS[0]}"; return "${PIPESTATUS[0]}"
}

case "${1:-plan}" in
  plan) plan ;;
  run)
    mkdir -p "$OUT"
    shift || true
    STAGES=("${@:-static build genesis fuzz}")
    [ "${#STAGES[@]}" -eq 0 ] || [ -z "${STAGES[0]}" ] && STAGES=(static build genesis fuzz)
    total=0
    for s in ${STAGES[@]}; do
      "stage_$s" || total=$((total+1))
    done
    echo ""
    [ "$total" -eq 0 ] && echo "PREVALIDATION: ALL STAGES PASS (logs: $OUT)" \
                       || { echo "PREVALIDATION: $total stage(s) FAILED (logs: $OUT)"; exit 1; }
    ;;
  *) echo "usage: $0 [plan|run [stage ...]]  (stages: static build genesis fuzz live)"; exit 1 ;;
esac
