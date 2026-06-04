#!/usr/bin/env bash
# =============================================================================
# init-gembad-multinode.sh — 4-validator gembad devnet (evmd + Phase 2 modules).
# Same as chain/scripts/init-multinode.sh but with the gembad binary and the
# reserve/faucet funded into MODULE accounts + custom-module genesis params.
#   WARNING: PUBLIC well-known devnet test keys + 'test' keyring. DEVNET ONLY.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
source "$SCRIPTS/gemba.params.sh"
source "$SCRIPTS/lib.sh"

EVMD="${GEMBAD:-/tmp/gembad}"
[ -x "$EVMD" ] || command -v "$EVMD" >/dev/null 2>&1 || { echo "FATAL: gembad not found"; exit 1; }
BASE="${BASE:-$HOME/.gembad-multinode}"
N=4
RS_RESERVE_ADDR="cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe"
FAUCET_ADDR="cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d"

VAL_MNEMONICS=(
  "***REMOVED-DEVNET-MNEMONIC***"
  "***REMOVED-DEVNET-MNEMONIC***"
  "***REMOVED-ROTATED-FAUCET-MNEMONIC***"
  "***REMOVED-DEVNET-MNEMONIC***"
)

echo ">> wiping $BASE"; rm -rf "$BASE"; N0="$BASE/node0"
gacct(){ "$EVMD" genesis add-genesis-account "$1" "$(gmb "$2")$BASE_DENOM" --keyring-backend "$KEYRING" --home "$N0"; }

for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"
  "$EVMD" init "gemba-val-$i" -o --chain-id "$COSMOS_CHAIN_ID" --home "$H" >/dev/null 2>&1
  echo "${VAL_MNEMONICS[$i]}" | "$EVMD" keys add "val$i" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$H" >/dev/null 2>&1
  [ "$i" -ne 0 ] && echo "${VAL_MNEMONICS[$i]}" | "$EVMD" keys add "val$i" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$N0" >/dev/null 2>&1
done
for b in foundation dao liquidity founder; do "$EVMD" keys add "$b" --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$N0" >/dev/null 2>&1; done

# allocation (fixed 100M GMB). circulation 10M = 4 x 2.5M; reserve+faucet to module accts.
for i in $(seq 0 $((N-1))); do gacct "val$i" "2500000"; done
gacct "$RS_RESERVE_ADDR" "$ALLOC_VAL_RESERVE"; gacct "$FAUCET_ADDR" "$ALLOC_FAUCET"
gacct foundation "$ALLOC_FOUNDATION"; gacct dao "$ALLOC_DAO"; gacct liquidity "$ALLOC_LIQUIDITY"; gacct founder "$ALLOC_FOUNDER"

GEN="$N0/config/genesis.json"; patch_economics "$GEN"
TMP="$(mktemp)"
# strip BaseAccounts at the module addresses (created lazily as ModuleAccounts)
jq --arg a "$RS_RESERVE_ADDR" --arg b "$FAUCET_ADDR" '.app_state.auth.accounts |= map(select(.address != $a and .address != $b))' "$GEN" >"$TMP" && mv "$TMP" "$GEN"
# custom module params (reward amplified for devnet visibility: 1000 GMB/block)
jq '.app_state.rewardstreamer.params.enabled=true | .app_state.rewardstreamer.params.reward_denom="agmb" | .app_state.rewardstreamer.params.blocks_per_year=2000
  | .app_state.feesplit.params.enabled=true | .app_state.feesplit.params.faucet_fee_ratio="0.400000000000000000" | .app_state.feesplit.params.faucet_account="faucet"' "$GEN" >"$TMP" && mv "$TMP" "$GEN"

mkdir -p "$N0/config/gentx"
for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"
  [ "$i" -ne 0 ] && cp "$GEN" "$H/config/genesis.json"
  "$EVMD" genesis gentx "val$i" "$(gmb "$SELF_BOND_GMB")$BASE_DENOM" --gas-prices "$MIN_GAS_PRICES_NODE" --keyring-backend "$KEYRING" --chain-id "$COSMOS_CHAIN_ID" --home "$H" >/dev/null 2>&1
  cp "$H"/config/gentx/*.json "$N0/config/gentx/" 2>/dev/null || true
done
"$EVMD" genesis collect-gentxs --home "$N0" >/dev/null 2>&1
"$EVMD" genesis validate-genesis --home "$N0"

declare -a IDS
for i in $(seq 0 $((N-1))); do
  [ "$i" -ne 0 ] && cp "$GEN" "$BASE/node$i/config/genesis.json"
  IDS[$i]="$("$EVMD" comet show-node-id --home "$BASE/node$i")"
done

for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"; C="$H/config/config.toml"; A="$H/config/app.toml"
  P2P=$((26656+i*100)); RPC=$((26657+i*100)); PROX=$((26658+i*100)); GRPC=$((9090+i*10)); API=$((1317+i*100)); JRPC=$((8545+i*100)); JWS=$((8546+i*100))
  tune_cometbft "$C"
  sed -i.bak "s|tcp://127.0.0.1:26658|tcp://127.0.0.1:$PROX|;s|tcp://127.0.0.1:26657|tcp://0.0.0.0:$RPC|;s|tcp://0.0.0.0:26656|tcp://0.0.0.0:$P2P|;s|localhost:6060|localhost:$((6060+i))|" "$C"
  sed -i.bak 's|^addr_book_strict = true|addr_book_strict = false|;s|^allow_duplicate_ip = false|allow_duplicate_ip = true|' "$C"
  PEERS=""; for j in $(seq 0 $((N-1))); do [ "$j" -eq "$i" ] && continue; PEERS="$PEERS,${IDS[$j]}@127.0.0.1:$((26656+j*100))"; done
  sed -i.bak "s|^persistent_peers = .*|persistent_peers = \"${PEERS#,}\"|" "$C"
  sed -i.bak "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICES_NODE\"|;s|^evm-chain-id = .*|evm-chain-id = $EVM_CHAIN_ID|;s|tcp://localhost:9090|tcp://localhost:$GRPC|;s|127.0.0.1:8545|127.0.0.1:$JRPC|;s|127.0.0.1:8546|127.0.0.1:$JWS|" "$A"
  sed -i.bak "/^\[api\]/,/^\[/ s|tcp://localhost:1317|tcp://localhost:$API|;/^\[api\]/,/^\[/ s|^enable = false|enable = true|" "$A"
  [ "$i" -eq 0 ] && sed -i.bak "/^\[json-rpc\]/,/^\[/ s|^enable = false|enable = true|" "$A"
  rm -f "$C.bak" "$A.bak"
done
echo "=== 4-validator gembad devnet at $BASE | node0: rpc 26657 json-rpc 8545 ==="
