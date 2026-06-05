#!/usr/bin/env bash
# =============================================================================
# init-local-testnet.sh — generate a 5-validator gemba-testnet-1 LOCALLY (dress
# rehearsal for the real multi-machine deploy in docs/runbooks/testnet-deploy.md).
# Produces the testnet genesis and a working 5-node local network on offset ports.
#   WARNING: PUBLIC/known testnet keys + 'test' keyring + VALUELESS tokens. Never
#   reuse on mainnet. The real deploy generates each validator's key on its own host.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
source "$SCRIPTS/gemba.params.sh"   # denom + economics constants
source "$SCRIPTS/lib.sh"            # patch_economics, gmb, tune_cometbft
source "$HERE/testnet.params.sh"

EVMD="${GEMBAD:-/tmp/gembad}"
[ -x "$EVMD" ] || command -v "$EVMD" >/dev/null 2>&1 || { echo "FATAL: gembad not found"; exit 1; }
BASE="${BASE:-$HOME/.gemba-testnet}"
N="$TN_VALIDATORS"
RS_RESERVE_ADDR="cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe"  # rewardstreamer
FAUCET_MODULE_ADDR="cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d" # faucet module acct

echo ">> wiping $BASE"; rm -rf "$BASE"; N0="$BASE/node0"
gacct(){ "$EVMD" genesis add-genesis-account "$1" "$(gmb "$2")$BASE_DENOM" --keyring-backend "$KEYRING" --home "$N0"; }

for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"
  "$EVMD" init "gemba-tn-val-$i" -o --chain-id "$TN_COSMOS_CHAIN_ID" --home "$H" >/dev/null 2>&1
  "$EVMD" keys add "val$i" --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$H" >/dev/null 2>&1
  # mirror each validator's address into node0's keyring for add-genesis-account
  ADDR=$("$EVMD" keys show "val$i" -a --keyring-backend "$KEYRING" --home "$H")
  [ "$i" -ne 0 ] && "$EVMD" keys add "val$i" --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$N0" --address "$ADDR" 2>/dev/null || true
done
# drip faucet account (the faucet SERVICE controls this key) + non-voting reserves
echo "$TN_FAUCET_MNEMONIC" | "$EVMD" keys add tnfaucet --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$N0" >/dev/null 2>&1
for b in foundation dao liquidity founder; do "$EVMD" keys add "$b" --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$N0" >/dev/null 2>&1; done

# --- allocation (total 100,000,000 test GMB) ---
for i in $(seq 0 $((N-1))); do
  ADDR=$("$EVMD" keys show "val$i" -a --keyring-backend "$KEYRING" --home "$BASE/node$i")
  "$EVMD" genesis add-genesis-account "$ADDR" "$(gmb "$TN_VAL_EACH")$BASE_DENOM" --home "$N0"
done
gacct tnfaucet "$TN_FAUCET_ALLOC"
gacct "$RS_RESERVE_ADDR" "$TN_ALLOC_REWARD_RESERVE"
gacct "$FAUCET_MODULE_ADDR" "$TN_ALLOC_FAUCET_MODULE"
gacct foundation "$TN_ALLOC_FOUNDATION"; gacct dao "$TN_ALLOC_DAO"
gacct liquidity "$TN_ALLOC_LIQUIDITY"; gacct founder "$TN_ALLOC_FOUNDER"

GEN="$N0/config/genesis.json"; patch_economics "$GEN"
TMP="$(mktemp)"
# strip BaseAccounts at the module addresses (created lazily as ModuleAccounts)
jq --arg a "$RS_RESERVE_ADDR" --arg b "$FAUCET_MODULE_ADDR" '.app_state.auth.accounts |= map(select(.address != $a and .address != $b))' "$GEN" >"$TMP" && mv "$TMP" "$GEN"
# testnet conveniences: shorter unbonding; custom-module genesis (tail stays off)
jq --arg u "$TN_UNBONDING_TIME" '.app_state.staking.params.unbonding_time = $u' "$GEN" >"$TMP" && mv "$TMP" "$GEN"
# GENESIS FEE FIX (ADR-008a): set feemarket min_gas_price = 0 so zero-fee gentxs
# (MsgCreateValidator) pass InitChain — the cosmos MinGasPriceDecorator short-
# circuits on 0. base_fee (1 gwei) and node minimum-gas-prices (1 gwei) stay
# non-zero for runtime; restore min_gas_price=1e9 via governance post-launch.
# (The real multi-machine deploy MUST do this too — see docs/runbooks/testnet-deploy.md
# step 2c — because its gentxs are zero-fee; here gentxs carry --gas-prices, but we
# set it for parity with the documented launch path.)
jq '.app_state.feemarket.params.min_gas_price = "0.000000000000000000"' "$GEN" >"$TMP" && mv "$TMP" "$GEN"

mkdir -p "$N0/config/gentx"
for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"
  [ "$i" -ne 0 ] && cp "$GEN" "$H/config/genesis.json"
  "$EVMD" genesis gentx "val$i" "$(gmb "$TN_SELF_BOND_GMB")$BASE_DENOM" --gas-prices "$MIN_GAS_PRICES_NODE" --keyring-backend "$KEYRING" --chain-id "$TN_COSMOS_CHAIN_ID" --home "$H" >/dev/null 2>&1
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
  sed -i.bak 's|^addr_book_strict = true|addr_book_strict = false|;s|^allow_duplicate_ip = false|allow_duplicate_ip = true|;s|^prometheus = false|prometheus = true|' "$C"
  # offset the Prometheus port per node so 5-on-one-host don't collide on :26660
  # (on separate machines each keeps :26660; this matters only for local runs)
  sed -i.bak "s|^prometheus_listen_addr = .*|prometheus_listen_addr = \":$((26660+i))\"|" "$C"
  PEERS=""; for j in $(seq 0 $((N-1))); do [ "$j" -eq "$i" ] && continue; PEERS="$PEERS,${IDS[$j]}@127.0.0.1:$((26656+j*100))"; done
  sed -i.bak "s|^persistent_peers = .*|persistent_peers = \"${PEERS#,}\"|" "$C"
  sed -i.bak "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICES_NODE\"|;s|^evm-chain-id = .*|evm-chain-id = $TN_EVM_CHAIN_ID|;s|tcp://localhost:9090|tcp://localhost:$GRPC|;s|127.0.0.1:8545|127.0.0.1:$JRPC|;s|127.0.0.1:8546|127.0.0.1:$JWS|" "$A"
  sed -i.bak "/^\[api\]/,/^\[/ s|tcp://localhost:1317|tcp://localhost:$API|;/^\[api\]/,/^\[/ s|^enable = false|enable = true|" "$A"
  [ "$i" -eq 0 ] && sed -i.bak "/^\[json-rpc\]/,/^\[/ s|^enable = false|enable = true|" "$A"
  rm -f "$C.bak" "$A.bak"
done
echo "=== gemba-testnet-1 generated at $BASE ($N validators) ==="
echo "  chain-id $TN_COSMOS_CHAIN_ID | EVM chainId $TN_EVM_CHAIN_ID | drip faucet $TN_FAUCET_ADDR_0X ($TN_FAUCET_ALLOC GMB)"
echo "  node0: rpc 26657, json-rpc 8545, prometheus 26660 | start each: gembad start --home $BASE/nodeN ..."
echo "  the canonical genesis to distribute: $GEN"
