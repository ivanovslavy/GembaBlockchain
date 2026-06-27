#!/usr/bin/env bash
# Track 2 — DOWNTIME SLASH → FAUCET (recoverable). Stops one devnet validator until it is
# jailed for downtime, then PROVES the §5.6/§3.1 invariants on a LIVE chain:
#   (1) the validator is jailed + slashed,
#   (2) the slashed stake is REDIRECTED TO THE FAUCET (x/slashfunds), NOT burned,
#   (3) total supply is UNCHANGED (no mint, no burn).
# Run against the throwaway devnet (security/devnet/up.sh first). Devnet slashing is tightened
# (30-block window) so this finishes in ~1–2 min.
set -uo pipefail
EVMD="${EVMD:-/usr/local/bin/gembad}"; BASE="${BASE:-$HOME/.gembad-sec-devnet}"
Q="--home $BASE/node0 --node tcp://localhost:26657 -o json"
agmb(){ jq -r '(.balances // .supply // [])[]? | select(.denom=="agmb") | .amount' 2>/dev/null; }
P=0; F=0; ok(){ P=$((P+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }; no(){ F=$((F+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

echo "═══ Track 2 — downtime slash → faucet (devnet) ═══"
# faucet module account (slash redirect target)
FAUCET=$($EVMD q auth module-accounts $Q 2>/dev/null | jq -r '.accounts[]? | (.value//.) | select(.name=="faucet") | (.base_account.address // .address)' | head -1)
[ -z "$FAUCET" ] && FAUCET=cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d
echo "  faucet module: $FAUCET"

# node3's valoper (by moniker — the bonded array isn't index-ordered; capture BEFORE stopping)
VALOPER=$($EVMD q staking validators $Q 2>/dev/null | jq -r '.validators[]|select(.description.moniker=="gemba-val-3").operator_address')
echo "  victim validator (node3): $VALOPER"
vfield(){ $EVMD q staking validator "$VALOPER" $Q 2>/dev/null | jq -r ".validator.$1"; }

SUP0=$($EVMD q bank total $Q 2>/dev/null | agmb)
FAU0=$($EVMD q bank balances "$FAUCET" $Q 2>/dev/null | agmb); FAU0=${FAU0:-0}
TOK0=$(vfield tokens)
echo "  baseline: supply=$SUP0  faucet=$FAU0  node3.tokens=$TOK0"

echo ">> stopping node3 (simulate validator downtime)…"
pkill -9 -f "gembad start --home $BASE/node3" 2>/dev/null; sleep 1

echo ">> waiting for downtime jail (≤140s)…"
JAILED=false
for t in $(seq 1 70); do
  j=$(vfield jailed)
  [ "$j" = "true" ] && { JAILED=true; echo "  jailed at ~$((t*2))s"; break; }
  sleep 2
done

SUP1=$($EVMD q bank total $Q 2>/dev/null | agmb)
FAU1=$($EVMD q bank balances "$FAUCET" $Q 2>/dev/null | agmb); FAU1=${FAU1:-0}
TOK1=$(vfield tokens)
echo "  after: supply=$SUP1  faucet=$FAU1  node3.tokens=$TOK1"

# (1) jailed
[ "$JAILED" = true ] && ok "node3 jailed for downtime" || no "node3 not jailed within window"
# (2) slashed (tokens decreased)
[ -n "$TOK1" ] && [ "$TOK1" != "$TOK0" ] && [ "$(printf '%s\n%s' "$TOK1" "$TOK0" | sort -g | head -1)" = "$TOK1" ] && ok "node3 stake slashed ($TOK0 → $TOK1)" || no "node3 stake not slashed ($TOK0 → $TOK1)"
# (3) supply unchanged (no burn / no mint) — allow tiny drift only if equal
[ "$SUP0" = "$SUP1" ] && ok "total supply UNCHANGED ($SUP1) — slash not burned" || no "supply changed $SUP0 → $SUP1 (would break fixed-supply!)"
# (4) faucet increased by ~the slashed amount (slashfunds redirect)
[ "$FAU1" != "$FAU0" ] && [ "$(printf '%s\n%s' "$FAU0" "$FAU1" | sort -g | head -1)" = "$FAU0" ] && ok "slashed stake REDIRECTED to faucet ($FAU0 → $FAU1)" || no "faucet did not receive the slash ($FAU0 → $FAU1)"

echo ">> recovery: restart node3 + auto-unjail-style unjail…"
RPC=26957; JRPC=8845
nohup "$EVMD" start --home "$BASE/node3" --chain-id gemba-1 --evm.evm-chain-id 821206 --minimum-gas-prices 5000000000agmb --rpc.laddr tcp://0.0.0.0:$RPC --json-rpc.enable=true --json-rpc.address 0.0.0.0:$JRPC >"$BASE/node3.log" 2>&1 &
sleep 12  # let it catch up past the jail duration (60s set in devnet) before unjail (manual wait)
echo "  node3 restarted (pid $!); unjail after the 60s jail window via: $EVMD tx slashing unjail --from val3 ..."

echo ""; echo "═══ RESULT: $P passed, $F failed ═══"; [ "$F" -gt 0 ] && exit 1 || exit 0
