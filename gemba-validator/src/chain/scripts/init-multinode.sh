#!/usr/bin/env bash
# =============================================================================
# init-multinode.sh — initialize a 4-validator GembaBlockchain local devnet.
# Phase 1 (CLAUDE.md §13). BFT needs N >= 3f+1: 4 validators tolerate 1 down and
# keep producing blocks (CLAUDE.md §5.3). Same genesis economics as single-node.
# All 4 run on one machine on offset ports; node0 exposes the EVM JSON-RPC.
#
#   WARNING: PUBLIC well-known devnet test keys + 'test' keyring. DEVNET ONLY.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/gemba.params.sh"
source "$HERE/lib.sh"
require_tools

BASE="${BASE:-$HOME/.gemba-multinode}"
N=4

# 4 distinct, well-known devnet validator mnemonics (cosmos/evm dev0..dev3).
VAL_MNEMONICS=(
  "***REMOVED-DEVNET-MNEMONIC***"
  "***REMOVED-DEVNET-MNEMONIC***"
  "***REMOVED-ROTATED-FAUCET-MNEMONIC***"
  "***REMOVED-DEVNET-MNEMONIC***"
)

echo ">> wiping $BASE"
rm -rf "$BASE"
N0="$BASE/node0"

kr() { "$EVMD" keys add "$1" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$2" >/dev/null 2>&1; }
gacct() { "$EVMD" genesis add-genesis-account "$1" "$(gmb "$2")$BASE_DENOM" --keyring-backend "$KEYRING" --home "$N0"; }

# --- 1. init each node (random consensus key each) + put its val key in its keyring + node0's ---
for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"
  "$EVMD" init "gemba-val-$i" -o --chain-id "$COSMOS_CHAIN_ID" --home "$H" >/dev/null 2>&1
  echo "${VAL_MNEMONICS[$i]}" | "$EVMD" keys add "val$i" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$H" >/dev/null 2>&1
  # mirror into node0's keyring so add-genesis-account by name works (skip i=0: same dir)
  if [ "$i" -ne 0 ]; then
    echo "${VAL_MNEMONICS[$i]}" | "$EVMD" keys add "val$i" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$N0" >/dev/null 2>&1
  fi
done
# reserve bucket keys live in node0's keyring
for b in faucet valreserve foundation dao liquidity founder; do
  "$EVMD" keys add "$b" --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$N0" >/dev/null 2>&1
done

# --- 2. genesis allocation on node0 (fixed 100M GMB, §4.1) ---
# circulation 10% = 4 validators x 2,500,000 GMB (each self-bonds 1M below)
for i in $(seq 0 $((N-1))); do gacct "val$i" "2500000"; done
gacct faucet "$ALLOC_FAUCET"; gacct valreserve "$ALLOC_VAL_RESERVE"; gacct foundation "$ALLOC_FOUNDATION"
gacct dao "$ALLOC_DAO"; gacct liquidity "$ALLOC_LIQUIDITY"; gacct founder "$ALLOC_FOUNDER"

# --- 3. bake economics into node0 genesis ---
patch_economics "$N0/config/genesis.json"

# --- 4. each validator self-bonds 1M from its own home, gentxs collected on node0 ---
mkdir -p "$N0/config/gentx"
for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"
  # node0 genesis (with all accounts) is needed locally to build a valid gentx
  [ "$i" -ne 0 ] && cp "$N0/config/genesis.json" "$H/config/genesis.json"
  "$EVMD" genesis gentx "val$i" "$(gmb "$SELF_BOND_GMB")$BASE_DENOM" \
    --gas-prices "$MIN_GAS_PRICES_NODE" --keyring-backend "$KEYRING" \
    --chain-id "$COSMOS_CHAIN_ID" --home "$H" >/dev/null 2>&1
  cp "$H"/config/gentx/*.json "$N0/config/gentx/" 2>/dev/null || true
done
"$EVMD" genesis collect-gentxs --home "$N0" >/dev/null 2>&1
"$EVMD" genesis validate-genesis --home "$N0" >/dev/null

# --- 5. distribute final genesis + collect node ids ---
declare -a IDS
for i in $(seq 0 $((N-1))); do
  [ "$i" -ne 0 ] && cp "$N0/config/genesis.json" "$BASE/node$i/config/genesis.json"
  IDS[$i]="$("$EVMD" comet show-node-id --home "$BASE/node$i")"
done

# --- 6. per-node ports, peers, mempool, gas floor ---
for i in $(seq 0 $((N-1))); do
  H="$BASE/node$i"; C="$H/config/config.toml"; A="$H/config/app.toml"
  P2P=$((26656 + i*100)); RPC=$((26657 + i*100)); PROX=$((26658 + i*100))
  GRPC=$((9090 + i*10)); API=$((1317 + i*100)); JRPC=$((8545 + i*100)); JWS=$((8546 + i*100))

  tune_cometbft "$C"   # ~2s blocks + mempool type "app"
  sed -i.bak "s|tcp://127.0.0.1:26658|tcp://127.0.0.1:$PROX|" "$C"
  sed -i.bak "s|tcp://127.0.0.1:26657|tcp://0.0.0.0:$RPC|"    "$C"
  sed -i.bak "s|tcp://0.0.0.0:26656|tcp://0.0.0.0:$P2P|"      "$C"
  sed -i.bak "s|localhost:6060|localhost:$((6060+i))|"        "$C"
  sed -i.bak 's|^addr_book_strict = true|addr_book_strict = false|' "$C"
  sed -i.bak 's|^allow_duplicate_ip = false|allow_duplicate_ip = true|' "$C"

  # all-to-all persistent peers (every other node)
  PEERS=""
  for j in $(seq 0 $((N-1))); do
    [ "$j" -eq "$i" ] && continue
    PEERS="$PEERS,${IDS[$j]}@127.0.0.1:$((26656 + j*100))"
  done
  PEERS="${PEERS#,}"
  sed -i.bak "s|^persistent_peers = .*|persistent_peers = \"$PEERS\"|" "$C"

  # app.toml: gas floor (ADR-008a), EVM chainId, ports; JSON-RPC only on node0
  sed -i.bak "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICES_NODE\"|" "$A"
  sed -i.bak "s|^evm-chain-id = .*|evm-chain-id = $EVM_CHAIN_ID|" "$A"
  sed -i.bak "s|tcp://localhost:9090|tcp://localhost:$GRPC|" "$A"
  sed -i.bak "/^\[api\]/,/^\[/ s|tcp://localhost:1317|tcp://localhost:$API|" "$A"
  sed -i.bak "/^\[api\]/,/^\[/ s|^enable = false|enable = true|" "$A"
  sed -i.bak "s|127.0.0.1:8545|127.0.0.1:$JRPC|" "$A"
  sed -i.bak "s|127.0.0.1:8546|127.0.0.1:$JWS|" "$A"
  if [ "$i" -eq 0 ]; then
    sed -i.bak "/^\[json-rpc\]/,/^\[/ s|^enable = false|enable = true|" "$A"
  fi
  rm -f "$C.bak" "$A.bak"
done

echo ""
echo "=== 4-validator GembaBlockchain devnet initialized at $BASE ==="
echo "  chain-id $COSMOS_CHAIN_ID | EVM chainId $EVM_CHAIN_ID | 4 x self-bond $SELF_BOND_GMB GMB"
echo "  node0 ports -> p2p 26656 rpc 26657 json-rpc 8545 | nodeN offset by N*100"
echo "  BFT: tolerates 1 validator down (N>=3f+1, CLAUDE.md §5.3)"
echo "Next: $HERE/start-multinode.sh"
