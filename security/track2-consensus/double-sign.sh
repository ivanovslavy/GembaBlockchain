#!/usr/bin/env bash
# Track 2 — DOUBLE-SIGN → TOMBSTONE (IRREVERSIBLE — devnet ONLY, never on live!). Starts a
# SECOND instance of node2's validator (same priv_validator_key, fresh node_key, other ports)
# so the validator signs two conflicting votes at the same height → CometBFT evidence →
# the validator is TOMBSTONED (jailed forever) + slashed (double-sign fraction). Proves §5.6:
#   tombstone + slash, the slashed stake → FAUCET (not burned), total supply UNCHANGED.
# Run against the throwaway devnet only (security/devnet/up.sh first).
set -uo pipefail
EVMD="${EVMD:-/usr/local/bin/gembad}"; BASE="${BASE:-$HOME/.gembad-sec-devnet}"
Q="--home $BASE/node0 --node tcp://localhost:26657 -o json"
agmb(){ jq -r '(.balances // .supply // [])[]? | select(.denom=="agmb") | .amount' 2>/dev/null; }
vfield(){ $EVMD q staking validator "$VALOPER" $Q 2>/dev/null | jq -r ".validator.$1"; }
P=0; F=0; ok(){ P=$((P+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }; no(){ F=$((F+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }

echo "═══ Track 2 — double-sign → tombstone (devnet ONLY) ═══"
[ "$(curl -s --max-time 3 localhost:26657/status 2>/dev/null | jq -r '.result.node_info.network')" = "gemba-1" ] || { echo "  refusing: devnet (gemba-1) not detected on :26657"; exit 1; }
FAUCET=cosmos17s95c5jpc6x2l3edwh4dm8yhac68yru7cre47d
VALOPER=$($EVMD q staking validators $Q 2>/dev/null | jq -r '.validators[]|select(.description.moniker=="gemba-val-2").operator_address')
CONSADDR=$($EVMD q staking validator "$VALOPER" $Q 2>/dev/null | jq -r '.validator.consensus_pubkey.key' 2>/dev/null)
echo "  victim validator (node2): $VALOPER"

SUP0=$($EVMD q bank total $Q 2>/dev/null | agmb)
FAU0=$($EVMD q bank balances "$FAUCET" $Q 2>/dev/null | agmb); FAU0=${FAU0:-0}
TOK0=$(vfield tokens)
echo "  baseline: supply=$SUP0 faucet=$FAU0 node2.tokens=$TOK0"

DUP="$BASE/node2-dup"
echo ">> creating duplicate validator instance (same consensus key, fresh node_key)…"
rm -rf "$DUP"; cp -r "$BASE/node2" "$DUP"
rm -f "$DUP/config/node_key.json"                                   # fresh P2P identity (distinct node ID)
"$EVMD" comet unsafe-reset-all --home "$DUP" --keep-addr-book >/dev/null 2>&1 || true  # reset cs state but KEEP priv_validator_key (the consensus key) → it will re-sign
# keep the SAME priv_validator_key.json (the equivocation source); reset priv_validator_state so it signs
printf '{"height":"0","round":0,"step":0}' > "$DUP/data/priv_validator_state.json"
# distinct ports so it can run alongside node2
C="$DUP/config/config.toml"; A="$DUP/config/app.toml"
sed -i 's|tcp://0.0.0.0:26856|tcp://0.0.0.0:27656|; s|tcp://0.0.0.0:26857|tcp://0.0.0.0:27657|; s|tcp://127.0.0.1:26858|tcp://127.0.0.1:27658|' "$C"
sed -i 's|127.0.0.1:8745|127.0.0.1:8945|; s|127.0.0.1:8746|127.0.0.1:8946|; s|localhost:9110|localhost:9210|' "$A" 2>/dev/null
nohup "$EVMD" start --home "$DUP" --chain-id gemba-1 --evm.evm-chain-id 821206 --minimum-gas-prices 5000000000agmb \
  --rpc.laddr tcp://0.0.0.0:27657 --json-rpc.enable=false --grpc.enable=false --api.enable=false >"$BASE/node2-dup.log" 2>&1 &
DUPPID=$!; echo "  dup pid $DUPPID (rpc :27657)"

echo ">> waiting for equivocation evidence → tombstone (≤160s)…"
TOMB=false
for t in $(seq 1 80); do
  jailed=$(vfield jailed)
  # tombstoned shows in slashing signing-info; also a tombstoned val is jailed + cannot unjail
  if [ "$jailed" = "true" ]; then
    tb=$($EVMD q slashing signing-infos $Q 2>/dev/null | jq -r --arg c "$CONSADDR" '.info[]?|select(.tombstoned==true)' | head -c 5)
    TOMB=true; echo "  validator jailed at ~$((t*2))s (tombstone=$([ -n "$tb" ] && echo yes || echo checking))"; break
  fi
  sleep 2
done

SUP1=$($EVMD q bank total $Q 2>/dev/null | agmb)
FAU1=$($EVMD q bank balances "$FAUCET" $Q 2>/dev/null | agmb); FAU1=${FAU1:-0}
TOK1=$(vfield tokens)
TOMBFLAG=$($EVMD q slashing signing-infos $Q 2>/dev/null | jq -r '[.info[]?|select(.tombstoned==true)]|length')
echo "  after: supply=$SUP1 faucet=$FAU1 node2.tokens=$TOK1 tombstoned_count=$TOMBFLAG"

[ "$TOMB" = true ] && ok "node2 jailed (equivocation detected)" || no "no tombstone within window (double-sign timing — re-run)"
[ "${TOMBFLAG:-0}" -ge 1 ] 2>/dev/null && ok "a validator is TOMBSTONED (permanent)" || no "no tombstoned validator in signing-infos"
[ -n "$TOK1" ] && [ "$TOK1" != "$TOK0" ] && [ "$(printf '%s\n%s' "$TOK1" "$TOK0"|sort -g|head -1)" = "$TOK1" ] && ok "node2 stake slashed ($TOK0 → $TOK1)" || no "node2 stake not slashed ($TOK0 → $TOK1)"
[ "$SUP0" = "$SUP1" ] && ok "total supply UNCHANGED ($SUP1) — slash not burned" || no "supply changed $SUP0 → $SUP1!"
[ "$FAU1" != "$FAU0" ] && [ "$(printf '%s\n%s' "$FAU0" "$FAU1"|sort -g|head -1)" = "$FAU0" ] && ok "slashed stake REDIRECTED to faucet ($FAU0 → $FAU1)" || no "faucet did not receive the slash"

echo ">> cleanup: killing the duplicate instance"
kill -9 $DUPPID 2>/dev/null; rm -rf "$DUP"
echo ""; echo "═══ RESULT: $P passed, $F failed ═══"; [ "$F" -gt 0 ] && exit 1 || exit 0
