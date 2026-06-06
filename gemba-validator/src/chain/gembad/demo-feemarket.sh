#!/usr/bin/env bash
# =============================================================================
# demo-feemarket.sh — Phase 4 EIP-1559 fee demonstration (ADR-008 / ADR-008a):
# "low but non-zero, scaling with usage". Shows the base fee at the floor on an
# idle chain, climbing under load, and decaying back afterwards.
#
# Setup: start a gembad node with a SMALL block gas limit so the EIP-1559 target
# (= block max_gas / elasticity_multiplier) is easy to exceed for the demo. The
# real chain uses max_gas = 100,000,000 (ADR-012); here we lower it for visibility only:
#
#   GEMBAD=/tmp/gembad ./init-gembad.sh
#   jq '.consensus.params.block.max_gas="500000"' \
#      ~/.gembad-devnet/config/genesis.json | sponge ~/.gembad-devnet/config/genesis.json
#   /tmp/gembad start --home ~/.gembad-devnet ... (see init output)
#   ./demo-feemarket.sh
#
# Example output (target = 250000 gas):
#   IDLE   block 34: baseFee=1.000 gwei  gasUsed=0          <- non-zero floor
#   LOAD   block 44: baseFee=1.937 gwei  gasUsed=483000     <- > target -> rising
#          block 48: baseFee=3.010 gwei  gasUsed=189000
#   DECAY  block 50: baseFee=2.554 gwei  gasUsed=0          <- subsiding to floor
#
# DEVNET ONLY.
# =============================================================================
set -uo pipefail
RPC="${RPC:-http://localhost:8545}"
PK="${DEV0_PK:-0xREMOVED_DEVNET_TEST_KEY}" # DEVNET key
DEV0=0xC6Fe5D33615a1C52c08018c47E8Bc53646A0E101
DEV1=0x963EBDf2e1f8DB8707D05FC75bfeFFBa1B5BaC17
N="${N:-250}" # number of transfers to blast

samp() {
  local b u n
  n=$(cast block latest -f number --rpc-url "$RPC")
  b=$(cast block latest -f baseFeePerGas --rpc-url "$RPC")
  u=$(cast block latest -f gasUsed --rpc-url "$RPC")
  printf "  block %s: baseFee=%s gwei  gasUsed=%s\n" "$n" "$(python3 -c "print(f'{$b/1e9:.3f}')")" "$u"
}

echo "=== IDLE — base fee sits at the 1 gwei floor (non-zero, ADR-008a) ==="
for i in 1 2 3; do samp; sleep 2; done

echo "=== LOAD — blast $N transfers; base fee scales up with usage ==="
NONCE=$(cast nonce $DEV0 --rpc-url "$RPC")
for i in $(seq 0 $((N - 1))); do
  cast send $DEV1 --value 1 --private-key "$PK" --rpc-url "$RPC" --legacy \
    --gas-price 100000000000 --nonce $((NONCE + i)) --async >/dev/null 2>&1
done
for i in $(seq 1 12); do samp; sleep 2; done

echo "Done. Aggregate security budget = baseFee x gasUsed scales with usage,"
echo "with a non-zero floor when idle (ADR-008: fees carry a real security budget)."
