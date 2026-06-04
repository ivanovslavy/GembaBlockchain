#!/usr/bin/env bash
# =============================================================================
# lib.sh — shared helpers for GembaBlockchain devnet scripts
# Sourced by init-single-node.sh and init-multinode.sh. Not run directly.
# =============================================================================

# Locate the evmd binary (built by `make install` from the pinned cosmos/evm).
# Phase 1 uses the upstream evmd binary as-is; the rebrand to a `gembad` binary
# with a "gemba" bech32 prefix is a documented later customization (CLAUDE.md §0.10).
EVMD="${EVMD:-$(go env GOPATH 2>/dev/null)/bin/evmd}"
command -v "$EVMD" >/dev/null 2>&1 || EVMD="evmd"

require_tools() {
  command -v jq   >/dev/null 2>&1 || { echo "FATAL: jq not installed"; exit 1; }
  command -v "$EVMD" >/dev/null 2>&1 || { echo "FATAL: evmd not found (run: make install in cosmos/evm)"; exit 1; }
}

# gmb <whole-gmb> -> integer string in agmb (multiply by 1e18 by appending 18 zeros)
gmb() { printf '%s000000000000000000' "$1"; }

# patch_economics <genesis.json>
# Bakes every CLAUDE.md / ADR economic anchor into the genesis file in place.
# Idempotent (safe to re-run on a fresh genesis).
patch_economics() {
  local G="$1" T
  T="$(mktemp)"
  : "${BASE_DENOM:?source gemba.params.sh first}"

  # --- denom wiring: staking, gov, evm, mint all use agmb (CLAUDE.md §1, §4) ---
  jq --arg d "$BASE_DENOM" '
    .app_state.staking.params.bond_denom = $d
    | .app_state.staking.params.max_validators = ('"$MAX_VALIDATORS"' | tonumber)
    | .app_state.gov.params.min_deposit[0].denom = $d
    | .app_state.gov.params.expedited_min_deposit[0].denom = $d
    | .app_state.evm.params.evm_denom = $d
    | .app_state.mint.params.mint_denom = $d
  ' "$G" >"$T" && mv "$T" "$G"

  # --- ZERO INFLATION: no minting after genesis (CLAUDE.md §3.1, §4.2; ADR-008) ---
  jq '
    .app_state.mint.params.inflation_max          = "'"$MINT_INFLATION_MAX"'"
    | .app_state.mint.params.inflation_min        = "'"$MINT_INFLATION_MIN"'"
    | .app_state.mint.params.inflation_rate_change= "'"$MINT_INFLATION_RATE_CHANGE"'"
    | .app_state.mint.minter.inflation            = "'"$MINT_INFLATION"'"
  ' "$G" >"$T" && mv "$T" "$G"

  # --- EIP-1559 / fees: low but NON-ZERO, scaling with usage (ADR-008 / ADR-008a) ---
  # The non-zero min_gas_price floor is the key anchor — upstream defaults it to 0.
  jq '
    .app_state.feemarket.params.no_base_fee                 = false
    | .app_state.feemarket.params.base_fee                  = "'"$BASE_FEE"'"
    | .app_state.feemarket.params.min_gas_price             = "'"$MIN_GAS_PRICE"'"
    | .app_state.feemarket.params.elasticity_multiplier     = ('"$ELASTICITY_MULTIPLIER"' | tonumber)
    | .app_state.feemarket.params.base_fee_change_denominator = ('"$BASE_FEE_CHANGE_DENOMINATOR"' | tonumber)
  ' "$G" >"$T" && mv "$T" "$G"

  # --- bank denom metadata: REQUIRED for the EVM to derive 18 decimals + GMB display
  #     (x/vm/keeper/coin_info.go reads the display unit's exponent) ---
  jq --arg base "$BASE_DENOM" --arg disp "$DISPLAY_DENOM" '
    .app_state.bank.denom_metadata = [{
      "description":"Gemba — native staking and gas coin of GembaBlockchain",
      "denom_units":[
        {"denom":$base,"exponent":0,"aliases":["atto-gmb"]},
        {"denom":$disp,"exponent":18,"aliases":[]}
      ],
      "base":$base,"display":$disp,"name":"Gemba","symbol":$disp,"uri":"","uri_hash":""
    }]
  ' "$G" >"$T" && mv "$T" "$G"

  # --- EVM precompiles + native-coin ERC20 representation (mirror upstream, agmb) ---
  jq '.app_state.evm.params.active_static_precompiles = [
        "0x0000000000000000000000000000000000000100",
        "0x0000000000000000000000000000000000000400",
        "0x0000000000000000000000000000000000000800",
        "0x0000000000000000000000000000000000000801",
        "0x0000000000000000000000000000000000000802",
        "0x0000000000000000000000000000000000000803",
        "0x0000000000000000000000000000000000000804",
        "0x0000000000000000000000000000000000000805",
        "0x0000000000000000000000000000000000000806",
        "0x0000000000000000000000000000000000000807"
      ]' "$G" >"$T" && mv "$T" "$G"
  jq --arg d "$BASE_DENOM" '
    .app_state.erc20.native_precompiles = ["0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"]
    | .app_state.erc20.token_pairs = [{contract_owner:1,erc20_address:"0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",denom:$d,enabled:true}]
  ' "$G" >"$T" && mv "$T" "$G"

  # --- block gas cap + short DEVNET governance periods (fast iteration only) ---
  jq '.consensus.params.block.max_gas = "10000000"' "$G" >"$T" && mv "$T" "$G"
  jq '
    .app_state.gov.params.max_deposit_period   = "30s"
    | .app_state.gov.params.voting_period       = "30s"
    | .app_state.gov.params.expedited_voting_period = "15s"
  ' "$G" >"$T" && mv "$T" "$G"
}

# tune_cometbft <config.toml> — ~2s blocks (CLAUDE.md §1, §11) + EVM mempool
tune_cometbft() {
  local C="$1"
  sed -i.bak "s/^timeout_commit = .*/timeout_commit = \"$TIMEOUT_COMMIT\"/" "$C"
  # Cosmos EVM requires the application-side mempool (default is "flood").
  sed -i.bak 's/^type = "flood"/type = "app"/' "$C"
  rm -f "${C}.bak"
}
