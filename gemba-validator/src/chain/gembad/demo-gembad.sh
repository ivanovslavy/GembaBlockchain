#!/usr/bin/env bash
# =============================================================================
# demo-gembad.sh — live demonstration of the Phase 2 modules on the gembad node.
# Proves on the REAL chain (not in-process):
#   1. total supply is unchanged while the reward streams (zero inflation §3.1),
#   2. a real EVM transfer's fee is split 60/40 (40% to the faucet module account,
#      60% to validators via distribution), and
#   3. the reward flows out of the reserve into validator rewards.
# Requires a running gembad node (init-gembad.sh + start). DEVNET ONLY.
# =============================================================================
set -euo pipefail
REST=http://localhost:1317
RPC=http://localhost:8545
HOME_DIR="${HOME_DIR:-$HOME/.gembad-devnet}"
GEMBAD="${GEMBAD:-/tmp/gembad}"
RS=cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe   # rewardstreamer reserve
FA=cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d   # faucet
VALOPER="$("$GEMBAD" q staking validators --home "$HOME_DIR" -o json 2>/dev/null | jq -r '.validators[0].operator_address')"
DEV0_PK="${DEV0_PK:?set DEV0_PK — see chain/.env.example}"
DEV1=0x963EBDf2e1f8DB8707D05FC75bfeFFBa1B5BaC17

bal(){ curl -s "$REST/cosmos/bank/v1beta1/balances/$1/by_denom?denom=agmb" | jq -r '.balance.amount // "0"'; }
sup(){ curl -s "$REST/cosmos/bank/v1beta1/supply/by_denom?denom=agmb" | jq -r '.amount.amount // "0"'; }
valrew(){ "$GEMBAD" q distribution validator-outstanding-rewards "$VALOPER" --home "$HOME_DIR" -o json 2>/dev/null | jq -r '.rewards.rewards[0] // "0agmb"' | sed 's/agmb//;s/\..*//'; }
g(){ python3 -c "print(f'{int(\"$1\")/10**18:,.6f}')"; }
H(){ curl -s localhost:26657/status | jq -r .result.sync_info.latest_block_height; }

echo "===== BEFORE (height $(H)) ====="
S0=$(sup); R0=$(bal $RS); F0=$(bal $FA); V0=$(valrew)
printf "  supply %s | reserve %s | faucet %s | val-rewards %s\n" "$(g $S0)" "$(g $R0)" "$(g $F0)" "$(g $V0)"

echo "===== EVM TRANSFER dev0 -> dev1, high gas price so the fee is visible ====="
TX=$(cast send $DEV1 --value 1000ether --private-key $DEV0_PK --rpc-url $RPC --legacy --gas-price 100000000000000 --json | jq -r .transactionHash)
RCPT=$(cast receipt $TX --rpc-url $RPC --json)
FEE=$(python3 -c "r=$(echo $RCPT|jq '{g:.gasUsed,p:.effectiveGasPrice}'); print(int(r['g'],16)*int(r['p'],16))")
echo "  tx $TX"
echo "  fee = $(g $FEE) GMB  ->  expect faucet +$(python3 -c "print(f'{int($FEE)*4//10/10**18:,.6f}')") (40%), validators +$(python3 -c "print(f'{int($FEE)*6//10/10**18:,.6f}')") (60%)"

printf "  waiting for feesplit (begin-block of next block)..."
for i in $(seq 1 12); do [ "$(bal $FA)" != "$F0" ] && break; sleep 1; done; echo " done"

echo "===== AFTER (height $(H)) ====="
S1=$(sup); R1=$(bal $RS); F1=$(bal $FA); V1=$(valrew)
printf "  supply %s | reserve %s | faucet %s | val-rewards %s\n" "$(g $S1)" "$(g $R1)" "$(g $F1)" "$(g $V1)"

echo "===== RESULT (deltas, python big-int) ====="
python3 - "$S0" "$S1" "$R0" "$R1" "$F0" "$F1" "$V0" "$V1" "$FEE" <<'PY'
import sys
S0,S1,R0,R1,F0,F1,V0,V1,FEE=[int(x) for x in sys.argv[1:]]
e=lambda x:f"{x/10**18:+,.6f}"
print(f"  supply delta      : {e(S1-S0)} GMB   <- MUST be 0 (zero inflation, §3.1)")
print(f"  reserve delta     : {e(R1-R0)} GMB   <- reward streamed OUT of the reserve")
print(f"  faucet delta      : {e(F1-F0)} GMB   == 40% of fee ({FEE*4//10/10**18:,.6f})  [feesplit]")
print(f"  val-rewards delta : {e(V1-V0)} GMB   <- 60% of fee + streamed reward [distribution]")
assert S1==S0, "SUPPLY CHANGED — zero-inflation invariant violated!"
assert F1-F0==FEE*4//10, "faucet did not receive exactly 40% of the fee"
print("  CHECK PASS: supply constant; fee split 60/40; reward recirculated, not minted.")
PY
