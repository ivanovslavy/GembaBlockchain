#!/usr/bin/env bash
# =============================================================================
# init-gembad.sh — single-node devnet for the gembad binary (evmd + the Phase 2
# custom modules wired in). Same Phase 1 economics, PLUS:
#   - the 20M validator-reward reserve funded into the rewardstreamer MODULE
#     account, and the 30M faucet bucket into the faucet MODULE account (so the
#     Go modules can move them); and
#   - rewardstreamer/feesplit genesis params.
#
#   WARNING: PUBLIC well-known devnet test keys + 'test' keyring. DEVNET ONLY.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$HERE/../scripts"
source "$SCRIPTS/gemba.params.sh"
source "$SCRIPTS/lib.sh"

# Use the gembad binary (built by build-gembad.sh) instead of stock evmd.
EVMD="${GEMBAD:-/tmp/gembad}"
command -v "$EVMD" >/dev/null 2>&1 || [ -x "$EVMD" ] || { echo "FATAL: gembad not found at $EVMD (run build-gembad.sh)"; exit 1; }

# Deterministic module-account addresses (bech32 prefix "cosmos"):
RS_RESERVE_ADDR="cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe"  # rewardstreamer reserve
FAUCET_ADDR="cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d"      # faucet

HOME_DIR="${HOME_DIR:-$HOME/.gembad-devnet}"
MONIKER="${MONIKER:-gembad-devnet-0}"
VAL_MNEMONIC="${VAL_MNEMONIC:?set VAL_MNEMONIC — see chain/.env.example}"
DEV0_MNEMONIC="${DEV0_MNEMONIC:?set DEV0_MNEMONIC — see chain/.env.example}"
DEV1_MNEMONIC="${DEV1_MNEMONIC:?set DEV1_MNEMONIC — see chain/.env.example}"

echo ">> wiping $HOME_DIR"
rm -rf "$HOME_DIR"

kadd() { echo "$2" | "$EVMD" keys add "$1" --recover --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$HOME_DIR" >/dev/null 2>&1; }
knew() { "$EVMD" keys add "$1" --keyring-backend "$KEYRING" --algo "$KEYALGO" --home "$HOME_DIR" >/dev/null 2>&1; }
gacct() { "$EVMD" genesis add-genesis-account "$1" "$(gmb "$2")$BASE_DENOM" --keyring-backend "$KEYRING" --home "$HOME_DIR"; }

"$EVMD" config set client chain-id "$COSMOS_CHAIN_ID" --home "$HOME_DIR" >/dev/null
"$EVMD" config set client keyring-backend "$KEYRING" --home "$HOME_DIR" >/dev/null

kadd validator "$VAL_MNEMONIC"; kadd dev0 "$DEV0_MNEMONIC"; kadd dev1 "$DEV1_MNEMONIC"
for b in foundation dao liquidity founder; do knew "$b"; done

echo ">> init chain $COSMOS_CHAIN_ID (gembad, EVM chainId $EVM_CHAIN_ID)"
echo "$VAL_MNEMONIC" | "$EVMD" init "$MONIKER" -o --chain-id "$COSMOS_CHAIN_ID" --home "$HOME_DIR" --recover >/dev/null 2>&1

# --- allocation, fixed 100M GMB (§4.1). Reserve + faucet go to MODULE accounts ---
gacct validator "5000000"; gacct dev0 "3000000"; gacct dev1 "2000000"       # circulation 10M
gacct "$RS_RESERVE_ADDR" "$ALLOC_VAL_RESERVE"                                # 20M -> rewardstreamer module acct
gacct "$FAUCET_ADDR"     "$ALLOC_FAUCET"                                     # 30M -> faucet module acct
gacct foundation "$ALLOC_FOUNDATION"; gacct dao "$ALLOC_DAO"
gacct liquidity "$ALLOC_LIQUIDITY"; gacct founder "$ALLOC_FOUNDER"

GENESIS="$HOME_DIR/config/genesis.json"
patch_economics "$GENESIS"
tune_cometbft "$HOME_DIR/config/config.toml"

# add-genesis-account created plain BaseAccounts at the two MODULE addresses. The
# bank keeper panics ("account is not a module account") when a module sends
# to/from such an address, so strip those BaseAccount entries: the module accounts
# are then created lazily as proper ModuleAccounts on first use and the genesis
# balance (keyed by address in the bank store) persists. Supply is unaffected.
STRIP="$(mktemp)"
jq --arg a "$RS_RESERVE_ADDR" --arg b "$FAUCET_ADDR" \
  '.app_state.auth.accounts |= map(select(.address != $a and .address != $b))' \
  "$GENESIS" >"$STRIP" && mv "$STRIP" "$GENESIS"

# --- custom module genesis params ---
TMP="$(mktemp)"
# rewardstreamer: amplify the per-block reward for a VISIBLE devnet demo.
# Real default is 2,000,000 GMB / 15,778,476 blocks/yr; here blocks_per_year=2000
# => 1000 GMB streamed per block (clearly visible while the reserve drains).
jq '.app_state.rewardstreamer.params.enabled = true
  | .app_state.rewardstreamer.params.reward_denom = "agmb"
  | .app_state.rewardstreamer.params.blocks_per_year = 2000' "$GENESIS" >"$TMP" && mv "$TMP" "$GENESIS"
# feesplit: 40% of fees to the faucet (the spec default), explicit here.
jq '.app_state.feesplit.params.enabled = true
  | .app_state.feesplit.params.faucet_fee_ratio = "0.400000000000000000"
  | .app_state.feesplit.params.faucet_account = "faucet"' "$GENESIS" >"$TMP" && mv "$TMP" "$GENESIS"

APP="$HOME_DIR/config/app.toml"
sed -i.bak "s|^minimum-gas-prices = .*|minimum-gas-prices = \"$MIN_GAS_PRICES_NODE\"|" "$APP"
sed -i.bak "s|^evm-chain-id = .*|evm-chain-id = $EVM_CHAIN_ID|" "$APP"
sed -i.bak '/^\[api\]/,/^\[/ s/^enable = false/enable = true/' "$APP"
sed -i.bak '/^\[json-rpc\]/,/^\[/ s/^enable = false/enable = true/' "$APP"
rm -f "${APP}.bak"

echo ">> gentx: validator self-bonds $SELF_BOND_GMB GMB"
# --min-self-delegation MUST be >= the x/valgate floor (MIN_SELF_BOND_GMB), else valgate's
# AfterValidatorCreated hook rejects the gentx at InitChain (gentx defaults it to 1). And the
# self-bond must be <= the valgate max (regenesis cap); SELF_BOND_GMB is set within [min,max].
"$EVMD" genesis gentx validator "$(gmb "$SELF_BOND_GMB")$BASE_DENOM" \
  --min-self-delegation "$(gmb "$MIN_SELF_BOND_GMB")" \
  --gas-prices "$MIN_GAS_PRICES_NODE" --keyring-backend "$KEYRING" \
  --chain-id "$COSMOS_CHAIN_ID" --home "$HOME_DIR" >/dev/null 2>&1
"$EVMD" genesis collect-gentxs --home "$HOME_DIR" >/dev/null 2>&1
"$EVMD" genesis validate-genesis --home "$HOME_DIR"

echo ""
echo "=== gembad devnet initialized at $HOME_DIR ==="
echo "  rewardstreamer reserve : $RS_RESERVE_ADDR (20,000,000 GMB)"
echo "  faucet                 : $FAUCET_ADDR (30,000,000 GMB)"
echo "  per-block reward (dev)  : 1000 GMB | fee split 60/40"
echo "Start: GEMBAD=$EVMD $EVMD start --home $HOME_DIR --chain-id $COSMOS_CHAIN_ID --evm.evm-chain-id $EVM_CHAIN_ID --minimum-gas-prices $MIN_GAS_PRICES_NODE --json-rpc.enable --json-rpc.api eth,net,web3,txpool,debug --api.enable"
