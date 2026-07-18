#!/usr/bin/env bash
# =============================================================================
# start-multinode.sh — start all 4 validators of the local multi-node devnet.
# Logs to $BASE/node{i}/node.log. Stop with stop-multinode.sh.
# node0 exposes EVM JSON-RPC on 8545. Run init-multinode.sh first.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/gemba.params.sh"
source "$HERE/lib.sh"

BASE="${BASE:-$HOME/.gemba-multinode}"
N=4

for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"
  EXTRA=()
  if [ "$i" -eq 0 ]; then
    EXTRA=(--json-rpc.enable --json-rpc.address 127.0.0.1:8545 --json-rpc.ws-address 127.0.0.1:8546
           --json-rpc.api eth,net,web3,txpool,debug)
  else
    EXTRA=(--json-rpc.enable=false)
  fi
  nohup "$EVMD" start \
    --home "$H" \
    --chain-id "$COSMOS_CHAIN_ID" \
    --evm.evm-chain-id "$EVM_CHAIN_ID" \
    --minimum-gas-prices "$MIN_GAS_PRICES_NODE" \
    "${EXTRA[@]}" \
    --pruning nothing \
    --log_level "${LOGLEVEL:-info}" >"$H/node.log" 2>&1 &
  echo "started node$i (pid $!) -> $H/node.log"
done
echo "All 4 validators starting. Check: curl -s localhost:26657/status | jq .result.sync_info"
