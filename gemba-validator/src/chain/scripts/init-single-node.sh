#!/usr/bin/env bash
# =============================================================================
# init-single-node.sh — initialize a single-node GembaBlockchain local devnet
# Phase 1 (CLAUDE.md §13). Builds genesis with the §4.1 allocation and the
# ADR-008/008a economic anchors. Run start-single-node.sh afterwards.
#
#   WARNING: uses PUBLIC, well-known devnet test keys and the 'test' keyring.
#   DEVNET ONLY. Never reuse these keys or this keyring on any public network.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/gemba.params.sh"
source "$HERE/lib.sh"
require_tools

HOME_DIR="${HOME_DIR:-$HOME/.gemba-devnet}"
MONIKER="${MONIKER:-gemba-devnet-0}"

# Public, well-known devnet test mnemonics (cosmos/evm local_node defaults).
VAL_MNEMONIC="***REMOVED-DEVNET-MNEMONIC***"
# dev0 -> 0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101  (the MetaMask/Foundry demo account)
DEV0_MNEMONIC="***REMOVED-DEVNET-MNEMONIC***"
# dev1 -> 0x963EBDf2e1f8DB8707D05FC75bfeFFBa1B5BaC17  (transfer recipient)
DEV1_MNEMONIC="***REMOVED-DEVNET-MNEMONIC***"

echo ">> wiping $HOME_DIR"
rm -rf "$HOME_DIR"

kadd() { echo "$2" | "$EVMD" keys add "$1" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$HOME_DIR" >/dev/null 2>&1; }
knew() { "$EVMD" keys add "$1" --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$HOME_DIR" >/dev/null 2>&1; }
gacct() { "$EVMD" genesis add-genesis-account "$1" "$(gmb "$2")$BASE_DENOM" --keyring-backend "$KEYRING" --home "$HOME_DIR"; }

"$EVMD" config set client chain-id "$COSMOS_CHAIN_ID" --home "$HOME_DIR" >/dev/null
"$EVMD" config set client keyring-backend "$KEYRING" --home "$HOME_DIR" >/dev/null

# --- keys: 3 circulation accounts + 6 non-voting reserve buckets ---
kadd validator "$VAL_MNEMONIC"
kadd dev0 "$DEV0_MNEMONIC"
kadd dev1 "$DEV1_MNEMONIC"
for b in faucet valreserve foundation dao liquidity founder; do knew "$b"; done

echo ">> init chain $COSMOS_CHAIN_ID (EVM chainId $EVM_CHAIN_ID)"
echo "$VAL_MNEMONIC" | "$EVMD" init "$MONIKER" -o --chain-id "$COSMOS_CHAIN_ID" --home "$HOME_DIR" --recover >/dev/null 2>&1

# --- genesis allocation, fixed supply N = 100,000,000 GMB (CLAUDE.md §4.1) ---
# circulation (10%, the voting base):
gacct validator "5000000"      # self-bonds 1M below; rest liquid
gacct dev0      "3000000"
gacct dev1      "2000000"
# reserves (90%, non-voting — held but never staked):
gacct faucet     "$ALLOC_FAUCET"
gacct valreserve "$ALLOC_VAL_RESERVE"
gacct foundation "$ALLOC_FOUNDATION"
gacct dao        "$ALLOC_DAO"
gacct liquidity  "$ALLOC_LIQUIDITY"
gacct founder    "$ALLOC_FOUNDER"

# --- bake economics (denom, zero inflation, non-zero fee floor, metadata...) ---
GENESIS="$HOME_DIR/config/genesis.json"
patch_economics "$GENESIS"
tune_cometbft "$HOME_DIR/config/config.toml"

# --- app.toml: EVM chainId 821206, non-zero min gas price, enable APIs/JSON-RPC ---
APP="$HOME_DIR/config/app.toml"
sed -i.bak "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICES_NODE\"|" "$APP"
sed -i.bak "s|^evm-chain-id = .*|evm-chain-id = $EVM_CHAIN_ID|" "$APP"
# enable cosmos REST API, gRPC, EVM JSON-RPC (off by default)
sed -i.bak '/^\[api\]/,/^\[/ s/^enable = false/enable = true/' "$APP"
sed -i.bak '/^\[json-rpc\]/,/^\[/ s/^enable = false/enable = true/' "$APP"
rm -f "${APP}.bak"

# --- self-bond 1M GMB from the circulation pool (consensus power != reserves) ---
echo ">> gentx: validator self-bonds $SELF_BOND_GMB GMB"
"$EVMD" genesis gentx validator "$(gmb "$SELF_BOND_GMB")$BASE_DENOM" \
  --gas-prices "$MIN_GAS_PRICES_NODE" --keyring-backend "$KEYRING" \
  --chain-id "$COSMOS_CHAIN_ID" --home "$HOME_DIR" >/dev/null 2>&1
"$EVMD" genesis collect-gentxs --home "$HOME_DIR" >/dev/null 2>&1
"$EVMD" genesis validate-genesis --home "$HOME_DIR" >/dev/null

echo ""
echo "=== GembaBlockchain devnet initialized at $HOME_DIR ==="
echo "  cosmos-chain-id : $COSMOS_CHAIN_ID"
echo "  evm chainId     : $EVM_CHAIN_ID   (decimal; 0x$(printf '%x' "$EVM_CHAIN_ID") hex)"
echo "  denom           : $BASE_DENOM (display $DISPLAY_DENOM, $DECIMALS decimals)"
echo "  total supply    : 100,000,000 GMB (fixed; mint inflation = 0)"
echo "  min gas price   : $MIN_GAS_PRICES_NODE (non-zero floor — ADR-008a)"
echo "  demo account    : dev0 = 0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101"
echo "Next: $HERE/start-single-node.sh"
