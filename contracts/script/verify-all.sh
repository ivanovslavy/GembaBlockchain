#!/usr/bin/env bash
# =============================================================================
# verify-all.sh — verify every re-genesis contract on GembaScan (Blockscout),
# NO API key needed. Reads the forge broadcast files (DeployGovernance + DeployDex)
# and runs `forge verify-contract` against the self-hosted Blockscout verifier.
#
# Usage:  GEMBA_NETWORK=testnet|mainnet ./script/verify-all.sh
# The network is an EXPLICIT choice (owner 2026-07-17) — no silent testnet default.
#   testnet: 821207, testnet.gembascan.io verifier, rpc1.gembascan.io
#   mainnet: 821206, gembascan.io verifier, gmb1.gembascan.io
# Each is still overridable via VERIFIER_URL / RPC_URL / CHAIN_ID.
# Run AFTER the re-genesis deploys (#5 + DeployDex). The deploy scripts can also
# pass `--verify --verifier blockscout --verifier-url $VERIFIER_URL` to verify inline.
# =============================================================================
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$HERE"
case "${GEMBA_NETWORK:-}" in
  testnet)
    VERIFIER_URL="${VERIFIER_URL:-https://testnet.gembascan.io/api/}"
    RPC_URL="${RPC_URL:-https://rpc1.gembascan.io}"
    CHAIN_ID="${CHAIN_ID:-821207}"
    ;;
  mainnet)
    VERIFIER_URL="${VERIFIER_URL:-https://gembascan.io/api/}"
    RPC_URL="${RPC_URL:-https://gmb1.gembascan.io}"
    CHAIN_ID="${CHAIN_ID:-821206}"
    ;;
  *) echo "FATAL: set GEMBA_NETWORK=testnet or GEMBA_NETWORK=mainnet explicitly." >&2; exit 1 ;;
esac

# contractName -> fully-qualified source path (for the verifier)
declare -A PATHS=(
  [GembaTimelock]="src/governance/GembaTimelock.sol:GembaTimelock"
  [GembaVotes]="src/governance/GembaVotes.sol:GembaVotes"
  [GembaGovernor]="src/governance/GembaGovernor.sol:GembaGovernor"
  [EmergencyPause]="src/governance/EmergencyPause.sol:EmergencyPause"
  [PublicReserve]="src/reserves/PublicReserve.sol:PublicReserve"
  [FoundationTreasury]="src/reserves/FoundationTreasury.sol:FoundationTreasury"
  [DAOReserve]="src/reserves/DAOReserve.sol:DAOReserve"
  [ContingencyReserve]="src/reserves/ContingencyReserve.sol:ContingencyReserve"
  [ERC1967Proxy]="lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
  [WGMB]="src/dex/WGMB.sol:WGMB"
  [GembaSwapFactory]="src/dex/gembaswap/core/GembaSwapFactory.sol:GembaSwapFactory"
  [GembaSwapRouter02]="src/dex/gembaswap/periphery/GembaSwapRouter02.sol:GembaSwapRouter02"
  [GembaNativePoolFactory]="src/dex/GembaNativePoolFactory.sol:GembaNativePoolFactory"
  [LiquidityLocker]="src/dex/LiquidityLocker.sol:LiquidityLocker"
)

verify_one() {
  local ca="$1" name="$2" path="${PATHS[$2]:-}"
  [ -z "$path" ] && { echo "  SKIP $name ($ca): no path mapping"; return; }
  echo ">> verifying $name @ $ca"
  forge verify-contract "$ca" "$path" \
    --verifier blockscout --verifier-url "$VERIFIER_URL" \
    --rpc-url "$RPC_URL" --chain-id "$CHAIN_ID" \
    --guess-constructor-args --watch 2>&1 | grep -iE 'success|already verified|verified|error|fail' | head -3
}

shopt -s nullglob
BCS=(broadcast/DeployGovernance.s.sol/$CHAIN_ID/run-latest.json broadcast/DeployDex.s.sol/$CHAIN_ID/run-latest.json)
found=0
for bc in "${BCS[@]}"; do
  [ -f "$bc" ] || continue
  found=1
  echo "=== verifying contracts from $bc ==="
  while IFS=$'\t' read -r ca name; do
    [ -n "$ca" ] && [ "$ca" != "null" ] && verify_one "$ca" "$name"
  done < <(python3 -c "
import json,sys
d=json.load(open('$bc'))
for t in d['transactions']:
    ca=t.get('contractAddress'); nm=t.get('contractName')
    if ca and nm: print(ca+chr(9)+nm)
")
done
[ "$found" = 0 ] && { echo "No broadcast files found — run the deploys first (with CHAIN_ID=$CHAIN_ID)."; exit 1; }
echo "=== done. Check https://testnet.gembascan.io for green checkmarks. ==="
