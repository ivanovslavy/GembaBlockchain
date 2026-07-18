#!/usr/bin/env bash
# =============================================================================
# start-single-node.sh — start the single-node GembaBlockchain devnet.
# Endpoints (CLAUDE.md §11): CometBFT RPC 26657, gRPC 9090, REST 1317,
# EVM JSON-RPC 8545 (HTTP) / 8546 (WS).
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/gemba.params.sh"
source "$HERE/lib.sh"

HOME_DIR="${HOME_DIR:-$HOME/.gemba-devnet}"

exec "$EVMD" start \
  --home "$HOME_DIR" \
  --chain-id "$COSMOS_CHAIN_ID" \
  --evm.evm-chain-id "$EVM_CHAIN_ID" \
  --minimum-gas-prices "$MIN_GAS_PRICES_NODE" \
  --json-rpc.enable \
  --json-rpc.address 127.0.0.1:8545 \
  --json-rpc.ws-address 127.0.0.1:8546 \
  --json-rpc.api eth,net,web3,txpool,debug \
  --api.enable \
  --pruning nothing \
  --log_level "${LOGLEVEL:-info}"
