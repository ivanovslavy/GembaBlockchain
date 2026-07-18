#!/usr/bin/env bash
# =============================================================================
# bonded-ratio-exporter.sh — exports the BONDED RATIO as a first-class Prometheus
# metric (docs/risks.md ADR-008: with inflation disabled there is no dynamic-
# inflation lever, so the bonded ratio is the security KPI governance must defend —
# target ~66%, floor ~50%, red line ~33%).
#
# The security-relevant ratio is bonded / CIRCULATING (circulating = total supply
# minus the non-voting reserves, which are never staked, §3.4). We query the
# staking pool + bank supply + the known reserve balances and write a Prometheus
# textfile metric. Run on a cron/timer or as a sidecar; point node_exporter's
# textfile collector at $OUT.
#
#   REST_URL=http://localhost:1317 OUT=/var/lib/node_exporter/textfile/gemba.prom \
#     ./bonded-ratio-exporter.sh
# =============================================================================
set -euo pipefail
REST="${REST_URL:-http://localhost:1317}"
DENOM="${DENOM:-agmb}"
OUT="${OUT:-/tmp/gemba_bonded_ratio.prom}"

# Module accounts that hold non-voting supply (never staked, §3.4/§4.1). Module
# addresses are derived from the module NAME + bech32 prefix, so they are the SAME
# on devnet/testnet/mainnet — safe to keep as built-in defaults.
RESERVES=(
  cosmos1s32mhm7c0eest48njscsr5fnn2c42mr9w8cnqe # rewardstreamer (validator-reward reserve)
  cosmos1s9kaf3uygudq8ezy4nc38q8cuz5rfgujqz68e2 # tailreward buffer
  cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d # faucet (Public Reserve module acct)
)

# GENESIS-SEEDED reserves (foundation / dao / contingency / founder + any excluded
# EVM reserve-contract accounts) are chain-specific and MUST be supplied via
# RESERVES_EXTRA (space- or comma-separated bech32 list) — the same addresses the
# genesis was built with (init-gembad-mainnet.sh: FOUNDATION_ADDR / DAO_ADDR /
# CONTINGENCY_ADDR / FOUNDER_ADDR). Without them the reserve sum is understated and
# the bonded ratio — THE security KPI (ADR-008) — reads too low exactly when it
# matters, so on mainnet this exporter FAILS LOUD instead of lying quietly.
if [[ -n "${RESERVES_EXTRA:-}" ]]; then
  # shellcheck disable=SC2206 # deliberate word-split of the configured list
  RESERVES+=(${RESERVES_EXTRA//,/ })
fi

q() { curl -sf "$REST$1"; }

chain_id=$(q /cosmos/base/tendermint/v1beta1/node_info | jq -r '.default_node_info.network // empty')
if [[ "$chain_id" == "gemba-1" && -z "${RESERVES_EXTRA:-}" ]]; then
  echo "FATAL: mainnet (gemba-1) detected but RESERVES_EXTRA is unset — the bonded ratio" >&2
  echo "would be computed without the genesis-seeded reserves (foundation/dao/contingency/" >&2
  echo "founder) and silently under-report. Set RESERVES_EXTRA to the genesis addresses." >&2
  exit 1
fi

bonded=$(q /cosmos/staking/v1beta1/pool | jq -r '.pool.bonded_tokens')
total=$(q "/cosmos/bank/v1beta1/supply/by_denom?denom=$DENOM" | jq -r '.amount.amount')

reserve_sum=0
for a in "${RESERVES[@]}"; do
  b=$(q "/cosmos/bank/v1beta1/balances/$a/by_denom?denom=$DENOM" | jq -r '.balance.amount // "0"')
  reserve_sum=$(python3 -c "print($reserve_sum + int('$b'))")
done

read ratio circulating <<<"$(python3 -c "
b=int('$bonded'); t=int('$total'); r=$reserve_sum
circ=max(t-r,0)
print(f'{(b/circ if circ else 0):.6f} {circ}')
")"

tmp="$(mktemp)"
cat > "$tmp" <<EOF
# HELP gemba_bonded_tokens Total bonded (staked) GMB, base units.
# TYPE gemba_bonded_tokens gauge
gemba_bonded_tokens $bonded
# HELP gemba_circulating_supply Total supply minus non-voting reserves, base units.
# TYPE gemba_circulating_supply gauge
gemba_circulating_supply $circulating
# HELP gemba_bonded_ratio Bonded / circulating supply (the security KPI, ADR-008).
# TYPE gemba_bonded_ratio gauge
gemba_bonded_ratio $ratio
EOF
mv "$tmp" "$OUT"
echo "bonded_ratio=$ratio (bonded=$bonded circulating=$circulating) -> $OUT"
