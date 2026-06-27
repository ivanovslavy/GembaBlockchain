#!/usr/bin/env bash
# security/devnet/up.sh — throwaway local 4-validator devnet for DESTRUCTIVE consensus tests
# (double-sign→tombstone, downtime-slash→faucet). Isolated chain-id gemba-1 / EVM 821206 —
# NOT the live testnet (gemba-testnet-1 / 821207), so nothing here can touch production.
# Slashing is tightened (short window) so a downtime slash triggers in ~1 min.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export EVMD="${EVMD:-/usr/local/bin/gembad}"
export GEMBAD="$EVMD"   # init-gembad-multinode.sh reads $GEMBAD
export BASE="${BASE:-$HOME/.gembad-sec-devnet}"
N=4
command -v "$EVMD" >/dev/null || { echo "FATAL: gembad not found at $EVMD"; exit 1; }
. "$ROOT/chain/scripts/gemba.params.sh"

echo ">> init 4-node devnet at $BASE (binary $($EVMD version 2>&1|head -1))"
# throwaway devnet — generate 4 fresh BIP-39 mnemonics (these keys never touch production)
for i in 0 1 2 3; do
  v="DEV${i}_MNEMONIC"
  [ -z "${!v:-}" ] && export "$v"="$($EVMD keys mnemonic 2>/dev/null)"
done
[ -z "${DEV0_MNEMONIC:-}" ] && { echo "FATAL: could not generate mnemonics"; exit 1; }
BASE="$BASE" GEMBAD="$EVMD" EVMD="$EVMD" \
  DEV0_MNEMONIC="$DEV0_MNEMONIC" DEV1_MNEMONIC="$DEV1_MNEMONIC" DEV2_MNEMONIC="$DEV2_MNEMONIC" DEV3_MNEMONIC="$DEV3_MNEMONIC" \
  bash "$ROOT/chain/gembad/init-gembad-multinode.sh" >"$BASE.init.log" 2>&1 || { echo "init failed — see $BASE.init.log"; tail -8 "$BASE.init.log"; exit 1; }

echo ">> tighten slashing (fast downtime jail) + ensure mempool=app, propagate genesis"
GEN="$BASE/node0/config/genesis.json"; T="$BASE/g.tmp"
jq '.app_state.slashing.params.signed_blocks_window="30"
  | .app_state.slashing.params.min_signed_per_window="0.500000000000000000"
  | .app_state.slashing.params.downtime_jail_duration="60s"
  | .app_state.slashing.params.slash_fraction_downtime="0.010000000000000000"
  | .app_state.slashing.params.slash_fraction_double_sign="0.050000000000000000"' "$GEN" >"$T" && mv "$T" "$GEN"
for i in $(seq 1 $((N-1))); do cp "$GEN" "$BASE/node$i/config/genesis.json"; done
for i in $(seq 0 $((N-1))); do
  C="$BASE/node$i/config/config.toml"
  sed -i 's/^type = "flood"/type = "app"/' "$C"
  sed -i 's/^timeout_commit = .*/timeout_commit = "1s"/' "$C"
done

echo ">> start $N nodes"
for i in $(seq 0 $((N-1))); do
  RPC=$((26657+i*100)); JRPC=$((8545+i*100))
  nohup "$EVMD" start --home "$BASE/node$i" --chain-id "$COSMOS_CHAIN_ID" --evm.evm-chain-id "$EVM_CHAIN_ID" \
    --minimum-gas-prices "$MIN_GAS_PRICES_NODE" --rpc.laddr "tcp://0.0.0.0:$RPC" \
    --json-rpc.enable=true --json-rpc.address "0.0.0.0:$JRPC" >"$BASE/node$i.log" 2>&1 &
  echo "  node$i: pid $! | rpc :$RPC json-rpc :$JRPC | home $BASE/node$i"
done

echo ">> wait for block production (node0 :26657)"
for t in $(seq 1 30); do
  h=$(curl -s --max-time 3 localhost:26657/status 2>/dev/null | jq -r '.result.sync_info.latest_block_height // 0' 2>/dev/null)
  [ "${h:-0}" -ge 2 ] 2>/dev/null && { echo "  ✓ producing — height $h, $N validators"; exit 0; }
  sleep 2
done
echo "  !! devnet did not reach height 2 — check $BASE/node0.log"; tail -5 "$BASE/node0.log"; exit 1
