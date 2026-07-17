#!/usr/bin/env bash
# =============================================================================
# init-gembad-mainnet.sh — MAINNET genesis builder for gemba-1 (EVM 821206).
#
# Implements the DECIDED §B values of docs/mainnet-launch-hardening.md
# (2026-07-17, owner). This script handles NO PRIVATE KEYS WHATSOEVER: it takes
# public bech32 ADDRESSES via env and produces the genesis; validator keys are
# generated ON EACH VALIDATOR BOX during the key ceremony and enter only as
# gentx files (see docs/runbooks/mainnet-genesis-ceremony.md).
#
# Usage:
#   1) build    — build the PRE-GENTX genesis from addresses (env below)
#   2) collect  — merge the validators' gentx files, finalize, verify, hash
#   3) verify   — run the full assertion battery on an existing genesis
#
#   FOUNDER_ADDR=cosmos1... FOUNDATION_ADDR=... DAO_ADDR=... CONTINGENCY_ADDR=...
#   PUBLICFAUCET_ADDR=... VAL_ADDRS="cosmos1a cosmos1b cosmos1c cosmos1d" \
#     ./init-gembad-mainnet.sh build
#   GENTX_DIR=/path/to/gentxs ./init-gembad-mainnet.sh collect
#
# Env: GEMBAD (binary, default /tmp/gembad), OUT (default ~/.gembad-mainnet-genesis),
#      FEESPLIT_FAUCET_ACCOUNT (default "faucet" — the module account, same as the
#      testnet; switching the 40% fee inflow to the PublicReserve CONTRACT address
#      is a separate, deliberate decision — docs/tokenomics-pending.md "Genesis
#      mechanics" #2).
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
source "$SCRIPTS/gemba.params.sh"
source "$SCRIPTS/lib.sh"

EVMD="${GEMBAD:-/tmp/gembad}"
OUT="${OUT:-$HOME/.gembad-mainnet-genesis}"
GEN="$OUT/config/genesis.json"
CMD="${1:-}"

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq not installed"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "FATAL: python3 not installed"; exit 1; }

# ---------------------------------------------------------------------------
# DECIDED §B GENESIS VALUES (docs/mainnet-launch-hardening.md, 2026-07-17)
# ---------------------------------------------------------------------------
GOV_VOTING_PERIOD="259200s"            # 3 days
GOV_EXPEDITED_VOTING_PERIOD="86400s"   # 1 day (< voting_period, SDK requirement)
GOV_MAX_DEPOSIT_PERIOD="259200s"       # 3 days
GOV_MIN_DEPOSIT_GMB="10000"            # 10,000 GMB (devnet 1e7 agmb ≈ 0 = spam risk)
GOV_EXPEDITED_MIN_DEPOSIT_GMB="50000"  # SDK-conventional 5× the normal deposit
GOV_QUORUM="0.334000000000000000"
GOV_THRESHOLD="0.500000000000000000"
GOV_EXPEDITED_THRESHOLD="0.667000000000000000"   # Critical ≥ 66%
STAKING_UNBONDING_TIME="1814400s"      # 21 days — the slashing/security window
# rewardstreamer — measured 2.402s avg block time on the live testnet (100k blocks):
RS_ANNUAL_REWARD_GMB="2000000"         # 2M GMB/year from the 20M reserve (~10y runway)
RS_BLOCKS_PER_YEAR="13140000"          # ~2.4s blocks; re-measure mainnet weeks 1-4
FP_BLOCKS_PER_DAY="36000"              # ~2.4s blocks (devnet 28800 is NOT for mainnet)
FP_RATE_PER_DAY="0.010000000000000000" # 1% of stake per day…
FP_FLOOR_GMB="10"                      # …but never below 10 GMB/day…
FP_CAP_GMB="100"                       # …and never above 100 GMB/day per validator
FP_MAX_TOTAL_GMB="5479"                # M4 aggregate budget = 2M/365 — hard emission backstop
# valgate (H1 — explicit, a reviewer must SEE the numbers, not trust code defaults):
VG_MIN_SELF_BOND_GMB="$MIN_SELF_BOND_GMB"   # 1,000
VG_MAX_SELF_BOND_GMB="10000"
VG_MAX_DAILY_BOND_INCREASE_GMB="50"
# Deterministic module accounts (derived from module names — same on any gembad chain):
RS_RESERVE_ADDR="cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe"   # x/rewardstreamer (20M reserve)
FAUCET_ADDR="cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d"       # feesplit "faucet" (30M Public Reserve)

require_bin() { [ -x "$EVMD" ] || command -v "$EVMD" >/dev/null 2>&1 || { echo "FATAL: gembad not found at \$GEMBAD=$EVMD (run build-gembad.sh)"; exit 1; }; }
gacct() { "$EVMD" genesis add-genesis-account "$1" "$(gmb "$2")$BASE_DENOM" --home "$OUT"; }

build() {
  require_bin
  : "${FOUNDER_ADDR:?set FOUNDER_ADDR (bech32, from the key ceremony)}"
  : "${FOUNDATION_ADDR:?set FOUNDATION_ADDR}"
  : "${DAO_ADDR:?set DAO_ADDR}"
  : "${CONTINGENCY_ADDR:?set CONTINGENCY_ADDR}"
  : "${PUBLICFAUCET_ADDR:?set PUBLICFAUCET_ADDR}"
  : "${VAL_ADDRS:?set VAL_ADDRS — space-separated validator ACCOUNT addresses (min 4)}"
  read -r -a VALS <<<"$VAL_ADDRS"
  [ "${#VALS[@]}" -ge 4 ] || { echo "FATAL: BFT needs ≥4 genesis validators (got ${#VALS[@]}) — CLAUDE.md §5.3"; exit 1; }

  echo ">> building PRE-GENTX mainnet genesis in $OUT (chain-id $COSMOS_CHAIN_ID / EVM $EVM_CHAIN_ID)"
  rm -rf "$OUT"
  "$EVMD" init "gemba-genesis" -o --chain-id "$COSMOS_CHAIN_ID" --home "$OUT" >/dev/null 2>&1

  # --- allocation (fixed 100M GMB; CLAUDE.md §4.1, decision 2026-06-29) -------------
  # Validators get SELF_BOND_GMB + 1 each (the +1 covers the 5-gwei gentx fee that the
  # ante charges at InitChain BEFORE the self-bond — an exact balance can't cover both).
  VAL_ALLOC=$((SELF_BOND_GMB + 1))
  VAL_ENTRY_TOTAL=$((${#VALS[@]} * VAL_ALLOC))
  FOUNDER_EOA=$((ALLOC_FOUNDER - VAL_ENTRY_TOTAL - PUBLIC_FAUCET_SEED))
  for v in "${VALS[@]}"; do gacct "$v" "$VAL_ALLOC"; done
  gacct "$RS_RESERVE_ADDR" "$ALLOC_VAL_RESERVE"      # 20M — validator-reward reserve (module)
  gacct "$FAUCET_ADDR" "$ALLOC_PUBLIC_RESERVE"       # 30M — Public Reserve (feesplit faucet acct)
  gacct "$FOUNDATION_ADDR" "$ALLOC_FOUNDATION"       # 15M
  gacct "$DAO_ADDR" "$ALLOC_DAO"                     # 10M
  gacct "$CONTINGENCY_ADDR" "$ALLOC_CONTINGENCY"     # 20M
  gacct "$PUBLICFAUCET_ADDR" "$PUBLIC_FAUCET_SEED"   # 100k — small public drip faucet seed
  gacct "$FOUNDER_ADDR" "$FOUNDER_EOA"               # ~4.86M — founder ops/trading stock
  # NO onramp account: GembaOnRamp was removed 2026-07-17; sales run via the dispenser.

  patch_economics "$GEN"   # denoms, zero inflation, 5-gwei feemarket, metadata, precompiles

  local T; T="$(mktemp)"
  # strip module BaseAccounts (recreated lazily as ModuleAccounts at InitChain)
  jq --arg a "$RS_RESERVE_ADDR" --arg b "$FAUCET_ADDR" \
    '.app_state.auth.accounts |= map(select(.address != $a and .address != $b))' "$GEN" >"$T" && mv "$T" "$GEN"

  # --- MAINNET overrides of the devnet-loose values patch_economics leaves behind ---
  jq --arg dep "$(gmb "$GOV_MIN_DEPOSIT_GMB")" --arg edep "$(gmb "$GOV_EXPEDITED_MIN_DEPOSIT_GMB")" '
      .app_state.gov.params.voting_period            = "'"$GOV_VOTING_PERIOD"'"
    | .app_state.gov.params.expedited_voting_period  = "'"$GOV_EXPEDITED_VOTING_PERIOD"'"
    | .app_state.gov.params.max_deposit_period       = "'"$GOV_MAX_DEPOSIT_PERIOD"'"
    | .app_state.gov.params.min_deposit[0].amount    = $dep
    | .app_state.gov.params.expedited_min_deposit[0].amount = $edep
    | .app_state.gov.params.quorum                   = "'"$GOV_QUORUM"'"
    | .app_state.gov.params.threshold                = "'"$GOV_THRESHOLD"'"
    | .app_state.gov.params.expedited_threshold      = "'"$GOV_EXPEDITED_THRESHOLD"'"
    | .app_state.staking.params.unbonding_time       = "'"$STAKING_UNBONDING_TIME"'"
  ' "$GEN" >"$T" && mv "$T" "$GEN"

  # valgate (H1): explicit numbers, not code defaults
  jq '
      .app_state.valgate.params.min_self_bond           = "'"$(gmb "$VG_MIN_SELF_BOND_GMB")"'"
    | .app_state.valgate.params.max_self_bond           = "'"$(gmb "$VG_MAX_SELF_BOND_GMB")"'"
    | .app_state.valgate.params.max_daily_bond_increase = "'"$(gmb "$VG_MAX_DAILY_BOND_INCREASE_GMB")"'"
  ' "$GEN" >"$T" && mv "$T" "$GEN"

  # rewardstreamer: the FORMULA is the mainnet reward model. The LEGACY fixed stream is
  # explicitly DISABLED so a governance formula kill-switch (MsgUpdateFormulaParams
  # enabled=false) is a FULL payout stop — with legacy enabled it would silently fall
  # back to the fixed 2M/yr stream (see x/rewardstreamer/keeper/abci.go). Governance can
  # still enable the legacy stream later via MsgUpdateParams if ever wanted.
  jq '
      .app_state.rewardstreamer.params.enabled         = false
    | .app_state.rewardstreamer.params.reward_denom    = "'"$BASE_DENOM"'"
    | .app_state.rewardstreamer.params.annual_reward   = "'"$(gmb "$RS_ANNUAL_REWARD_GMB")"'"
    | .app_state.rewardstreamer.params.blocks_per_year = ('"$RS_BLOCKS_PER_YEAR"' | tonumber)
    | .app_state.rewardstreamer.formula_params = {
        "enabled": true,
        "rate_per_day":   "'"$FP_RATE_PER_DAY"'",
        "floor_per_day":  "'"$(gmb "$FP_FLOOR_GMB")"'",
        "cap_per_day":    "'"$(gmb "$FP_CAP_GMB")"'",
        "blocks_per_day": ('"$FP_BLOCKS_PER_DAY"' | tonumber),
        "reward_denom":   "'"$BASE_DENOM"'",
        "max_total_per_day": "'"$(gmb "$FP_MAX_TOTAL_GMB")"'"
      }
  ' "$GEN" >"$T" && mv "$T" "$GEN"

  # feesplit: 60/40 to validators/faucet (CLAUDE.md §5.4)
  jq '
      .app_state.feesplit.params.enabled          = true
    | .app_state.feesplit.params.faucet_fee_ratio = "0.400000000000000000"
    | .app_state.feesplit.params.faucet_account   = "'"${FEESPLIT_FAUCET_ACCOUNT:-faucet}"'"
  ' "$GEN" >"$T" && mv "$T" "$GEN"

  verify
  echo ""
  echo ">> PRE-GENTX genesis ready: $GEN"
  echo ">> Next: distribute it to every validator box; each runs its gentx with"
  echo ">>   gembad genesis gentx <key> $(gmb "$SELF_BOND_GMB")$BASE_DENOM --min-self-delegation $(gmb "$MIN_SELF_BOND_GMB") \\"
  echo ">>     --gas-prices $MIN_GAS_PRICES_NODE --chain-id $COSMOS_CHAIN_ID"
  echo ">> then: GENTX_DIR=<dir with all gentx *.json> $0 collect"
}

collect() {
  require_bin
  : "${GENTX_DIR:?set GENTX_DIR — directory holding every validator gentx *.json}"
  [ -f "$GEN" ] || { echo "FATAL: no pre-gentx genesis at $GEN (run build first)"; exit 1; }
  local n; n=$(ls "$GENTX_DIR"/*.json 2>/dev/null | wc -l)
  [ "$n" -ge 4 ] || { echo "FATAL: need ≥4 gentx files, found $n in $GENTX_DIR"; exit 1; }
  echo ">> collecting $n gentx files"
  mkdir -p "$OUT/config/gentx"; cp "$GENTX_DIR"/*.json "$OUT/config/gentx/"
  "$EVMD" genesis collect-gentxs --home "$OUT" >/dev/null 2>&1
  "$EVMD" genesis validate-genesis --home "$OUT"
  verify
  echo ""
  echo ">> FINAL mainnet genesis: $GEN"
  echo ">> sha256 (publish this; validators must verify before starting):"
  sha256sum "$GEN"
}

# --- assertion battery: every decided §B value, verified against the produced file ---
verify() {
  [ -f "$GEN" ] || { echo "FATAL: no genesis at $GEN"; exit 1; }
  GEN="$GEN" BASE_DENOM="$BASE_DENOM" COSMOS_CHAIN_ID="$COSMOS_CHAIN_ID" \
  GOV_VOTING_PERIOD="$GOV_VOTING_PERIOD" GOV_EXPEDITED_VOTING_PERIOD="$GOV_EXPEDITED_VOTING_PERIOD" \
  GOV_MIN_DEPOSIT="$(gmb "$GOV_MIN_DEPOSIT_GMB")" GOV_QUORUM="$GOV_QUORUM" GOV_THRESHOLD="$GOV_THRESHOLD" \
  GOV_EXPEDITED_THRESHOLD="$GOV_EXPEDITED_THRESHOLD" STAKING_UNBONDING_TIME="$STAKING_UNBONDING_TIME" \
  MIN_GAS_PRICE="$MIN_GAS_PRICE" MAX_VALIDATORS="$MAX_VALIDATORS" \
  RS_ANNUAL_REWARD="$(gmb "$RS_ANNUAL_REWARD_GMB")" RS_BLOCKS_PER_YEAR="$RS_BLOCKS_PER_YEAR" \
  FP_BLOCKS_PER_DAY="$FP_BLOCKS_PER_DAY" FP_RATE_PER_DAY="$FP_RATE_PER_DAY" \
  FP_FLOOR="$(gmb "$FP_FLOOR_GMB")" FP_CAP="$(gmb "$FP_CAP_GMB")" FP_MAX_TOTAL="$(gmb "$FP_MAX_TOTAL_GMB")" \
  VG_MIN="$(gmb "$VG_MIN_SELF_BOND_GMB")" VG_MAX="$(gmb "$VG_MAX_SELF_BOND_GMB")" \
  VG_DAILY="$(gmb "$VG_MAX_DAILY_BOND_INCREASE_GMB")" \
  RS_RESERVE_ADDR="$RS_RESERVE_ADDR" FAUCET_ADDR="$FAUCET_ADDR" \
  python3 - <<'PY'
import json, os, sys

g = json.load(open(os.environ["GEN"]))
app = g["app_state"]
env = os.environ
failures = []

def check(name, got, want):
    ok = str(got) == str(want)
    print(f"  [{'OK' if ok else 'FAIL'}] {name}: {got}" + ("" if ok else f"  (want {want})"))
    if not ok:
        failures.append(name)

print("== identity ==")
check("chain_id", g["chain_id"], env["COSMOS_CHAIN_ID"])

print("== supply (exact, bigint) ==")
denom = env["BASE_DENOM"]
total = sum(int(c["amount"]) for b in app["bank"]["balances"] for c in b["coins"] if c["denom"] == denom)
check("total supply (agmb)", total, 100_000_000 * 10**18)
reserve = sum(int(c["amount"]) for b in app["bank"]["balances"] if b["address"] == env["RS_RESERVE_ADDR"]
              for c in b["coins"] if c["denom"] == denom)
check("rewardstreamer reserve (20M)", reserve, 20_000_000 * 10**18)
pubres = sum(int(c["amount"]) for b in app["bank"]["balances"] if b["address"] == env["FAUCET_ADDR"]
             for c in b["coins"] if c["denom"] == denom)
check("Public Reserve (30M)", pubres, 30_000_000 * 10**18)

print("== zero inflation ==")
check("mint.inflation", app["mint"]["minter"]["inflation"], "0.000000000000000000")
check("mint.inflation_max", app["mint"]["params"]["inflation_max"], "0.000000000000000000")

print("== feemarket (L2) ==")
check("min_gas_price (5 gwei)", app["feemarket"]["params"]["min_gas_price"], env["MIN_GAS_PRICE"])
check("no_base_fee", app["feemarket"]["params"]["no_base_fee"], False)

print("== staking ==")
check("unbonding_time (21d)", app["staking"]["params"]["unbonding_time"], env["STAKING_UNBONDING_TIME"])
check("bond_denom", app["staking"]["params"]["bond_denom"], denom)
check("max_validators", app["staking"]["params"]["max_validators"], env["MAX_VALIDATORS"])

print("== gov (mainnet-tight, not devnet 30s) ==")
gov = app["gov"]["params"]
check("voting_period (3d)", gov["voting_period"], env["GOV_VOTING_PERIOD"])
check("expedited_voting_period (1d)", gov["expedited_voting_period"], env["GOV_EXPEDITED_VOTING_PERIOD"])
check("min_deposit (10,000 GMB)", gov["min_deposit"][0]["amount"], env["GOV_MIN_DEPOSIT"])
check("min_deposit denom", gov["min_deposit"][0]["denom"], denom)
check("quorum", gov["quorum"], env["GOV_QUORUM"])
check("threshold", gov["threshold"], env["GOV_THRESHOLD"])
check("expedited_threshold (≥66%)", gov["expedited_threshold"], env["GOV_EXPEDITED_THRESHOLD"])

print("== valgate (H1 — explicit) ==")
vg = app["valgate"]["params"]
check("min_self_bond (1,000)", vg["min_self_bond"], env["VG_MIN"])
check("max_self_bond (10,000)", vg["max_self_bond"], env["VG_MAX"])
check("max_daily_bond_increase (50)", vg["max_daily_bond_increase"], env["VG_DAILY"])

print("== rewardstreamer (M2/M4 — formula model, legacy OFF) ==")
rs, fp = app["rewardstreamer"]["params"], app["rewardstreamer"]["formula_params"]
check("legacy stream disabled", rs["enabled"], False)
check("annual_reward (2M, on record)", rs["annual_reward"], env["RS_ANNUAL_REWARD"])
check("blocks_per_year (13.14M)", rs["blocks_per_year"], env["RS_BLOCKS_PER_YEAR"])
check("formula enabled", fp["enabled"], True)
check("rate_per_day (1%)", fp["rate_per_day"], env["FP_RATE_PER_DAY"])
check("floor_per_day (10)", fp["floor_per_day"], env["FP_FLOOR"])
check("cap_per_day (100)", fp["cap_per_day"], env["FP_CAP"])
check("blocks_per_day (36,000)", fp["blocks_per_day"], env["FP_BLOCKS_PER_DAY"])
check("max_total_per_day (5,479 — M4)", fp["max_total_per_day"], env["FP_MAX_TOTAL"])

print("== feesplit (60/40) ==")
fs = app["feesplit"]["params"]
check("enabled", fs["enabled"], True)
check("faucet_fee_ratio (0.4)", fs["faucet_fee_ratio"], "0.400000000000000000")
print(f"  [i ] faucet_account = {fs['faucet_account']}")

n_gentx = len(app.get("genutil", {}).get("gen_txs", []))
print(f"== genutil == {n_gentx} gentx(s) collected" + (" (pre-gentx stage)" if n_gentx == 0 else ""))

if failures:
    print(f"\nVERIFY FAILED — {len(failures)} mismatch(es): {failures}")
    sys.exit(1)
print("\nVERIFY OK — every decided §B value confirmed in the produced genesis.")
PY
}

case "$CMD" in
  build)   build ;;
  collect) collect ;;
  verify)  verify ;;
  *) echo "usage: $0 {build|collect|verify}   (see header for env)"; exit 1 ;;
esac
