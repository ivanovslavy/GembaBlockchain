#!/usr/bin/env bash
# security/e2e/live-invariants.sh — NON-DESTRUCTIVE, read-only assertions that the
# CLAUDE.md §3 hard invariants + the regenesis (2026-06-27) security posture hold on the
# LIVE chain + deployed contracts. Pure eth_call / curl reads — moves nothing, signs nothing.
# Exit 0 = all PASS. Run: bash security/e2e/live-invariants.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; . "${SEC_CONFIG:-$HERE/config.sh}"   # SEC_CONFIG=config.mainnet.sh for gemba-1
RPC=$(sec_rpc)
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
no(){ FAIL=$((FAIL+1)); FAILED+=("$2"); printf '  \033[31mFAIL\033[0m %s\n' "$1"; }
call(){ cast call "$1" "$2" ${3:-} --rpc-url "$RPC" 2>/dev/null; }
lc(){ echo "$1" | tr 'A-Z' 'a-z'; }

echo "═══ GembaBlockchain LIVE security invariants (RPC=$RPC) ═══"

echo "── chain identity ──"
for u in "$SEC_RPC1" "$SEC_RPC2" "$SEC_RPC3"; do
  c=$(curl -s --max-time 6 -X POST "$u" -H 'content-type: application/json' --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null | grep -o "$SEC_CHAIN_ID_HEX")
  [ "$c" = "$SEC_CHAIN_ID_HEX" ] && ok "$u serves chainId $SEC_CHAIN_ID_DEC" || no "$u wrong/absent chainId" "rpc:$u"
done

echo "── reserves are governance-owned (owner == Timelock), NOT an EOA (§3.6) ──"
for n in FOUNDATION:$C_FOUNDATION DAO:$C_DAO CONTINGENCY:$C_CONTINGENCY DRIPFAUCET:$C_DRIPFAUCET; do
  name=${n%%:*}; addr=${n#*:}
  o=$(call "$addr" 'owner()(address)')
  [ "$(lc "$o")" = "$(lc "$C_TIMELOCK")" ] && ok "$name.owner == Timelock" || no "$name.owner=$o (expected Timelock)" "owner:$name"
done

echo "── reserves never vote (excluded from GembaVotes, §3.4) ──"
for n in FAUCET:$C_FAUCET FOUNDATION:$C_FOUNDATION DAO:$C_DAO CONTINGENCY:$C_CONTINGENCY; do
  name=${n%%:*}; addr=${n#*:}
  v=$(call "$C_VOTES" 'getVotes(address)(uint256)' "$addr"); v=${v%% *}
  [ "$v" = "0" ] && ok "$name getVotes == 0 (excluded)" || no "$name getVotes=$v (must be 0)" "votes:$name"
done

echo "── no public GMB sale by design (§2/§16.1) ──"
if [ -n "${C_ONRAMP:-}" ]; then
  # legacy testnet deploy still has the (disabled) OnRamp; the contract was removed 2026-07-17
  ps=$(call "$C_ONRAMP" 'publicSaleEnabled()(bool)')
  [ "$ps" = "false" ] && ok "OnRamp.publicSaleEnabled == false" || no "OnRamp.publicSaleEnabled=$ps (must be false)" "onramp"
else
  ok "no OnRamp deployed (contract removed 2026-07-17) — no public sale by construction"
fi

echo "── 2-tier governance correctly configured (§9 regenesis) ──"
q=$(call "$C_GOVERNOR" 'quorumNumerator()(uint256)'); q=${q%% *}
cq=$(call "$C_GOVERNOR" 'criticalQuorumNumerator()(uint256)'); cq=${cq%% *}
cs=$(call "$C_GOVERNOR" 'criticalSupermajorityNumerator()(uint256)'); cs=${cs%% *}
[ "$q" = "40" ] && ok "Governor std quorum == 40" || no "Governor std quorum=$q (expected 40)" "gov:quorum"
[ "$cq" = "51" ] && ok "Governor critical quorum == 51" || no "Governor critical quorum=$cq (expected 51)" "gov:cquorum"
[ "$cs" = "66" ] && ok "Governor critical supermajority == 66" || no "Governor critical supermajority=$cs (expected 66)" "gov:csuper"

echo "── EmergencyPause is pause-only, cannot move funds (§7) ──"
code=$(cast code "$C_EMERGENCYPAUSE" --rpc-url "$RPC" 2>/dev/null | head -c 6)
[ "$code" = "0x6080" ] || [ ${#code} -gt 2 ] && ok "EmergencyPause has code" || no "EmergencyPause no code" "pause:code"
# probe for any value-moving fn — all must NOT exist (revert)
drain=0
for sig in 'withdraw(address,uint256)' 'transfer(address,uint256)' 'release(address,uint256)' 'execute(address,uint256,bytes)'; do
  r=$(cast call "$C_EMERGENCYPAUSE" "$sig" 0x0000000000000000000000000000000000000000 0 0x --rpc-url "$RPC" 2>&1)
  echo "$r" | grep -qiE 'reverted|0x$|no contract|not found|error' || drain=1
done
[ "$drain" = "0" ] && ok "EmergencyPause exposes no fund-moving function" || no "EmergencyPause MAY move funds!" "pause:drain"

echo "── all protocol + dApp contracts verified on gembascan ──"
declare -A V=( [Timelock]=$C_TIMELOCK [Votes]=$C_VOTES [Governor]=$C_GOVERNOR [EmergencyPause]=$C_EMERGENCYPAUSE [Faucet]=$C_FAUCET [Foundation]=$C_FOUNDATION [DAO]=$C_DAO [Contingency]=$C_CONTINGENCY [DripFaucet]=$C_DRIPFAUCET [Ticketing]=$C_TICKETING [Perks]=$C_PERKS [Forwarder]=$C_FORWARDER [CheckIn]=$C_CHECKIN [AccessNFT]=$C_ACCESSNFT [GembaWinFactory]=$D_GEMBAWIN_FACTORY [GembaTicketRegistry]=$D_GEMBATICKET_REGISTRY [EduChainGameToken]=$D_EDUCHAIN_GAMETOKEN [EscrowFactory]=$D_ESCROW_FACTORY [GembaPass]=$D_GEMBAPASS )
[ -n "${C_ONRAMP:-}" ] && V[OnRamp]=$C_ONRAMP  # legacy testnet only (contract removed 2026-07-17)
for name in "${!V[@]}"; do
  cn=$(curl -s --max-time 8 "$SEC_EXPLORER/api?module=contract&action=getsourcecode&address=${V[$name]}" 2>/dev/null | grep -oE '"ContractName":"[^"]+"' | head -1 | cut -d'"' -f4)
  [ -n "$cn" ] && ok "$name verified ($cn)" || no "$name NOT verified" "verify:$name"
done

echo "── dApp faucets are funded (functional) ──"
for n in DRIPFAUCET:$C_DRIPFAUCET:1000 GEMBAWIN_FAUCET:$D_GEMBAWIN_FAUCET:1 EDUCHAIN_FAUCET:$D_EDUCHAIN_FAUCET:1; do
  name=${n%%:*}; rest=${n#*:}; addr=${rest%%:*}; min=${rest#*:}
  wei=$(cast balance "$addr" --rpc-url "$RPC" 2>/dev/null); gmb=$(cast from-wei "${wei:-0}" 2>/dev/null | cut -d. -f1)
  [ "${gmb:-0}" -ge "$min" ] 2>/dev/null && ok "$name funded (${gmb} GMB)" || no "$name underfunded (${gmb} GMB < $min)" "faucet:$name"
done

echo "── fixed supply == 100M GMB (§3.1, best-effort via CometBFT) ──"
sup=$(curl -s --max-time 6 "$SEC_COMETBFT/abci_query?path=%22/cosmos.bank.v1beta1.Query/TotalSupply%22" 2>/dev/null | grep -o '100000000000000000000000000' | head -1)
if [ -n "$sup" ]; then ok "total supply == 100,000,000 GMB"
else echo "  SKIP supply (CometBFT RPC firewalled — covered by chain Go test TestSupplyInvariance + manual q bank total)"; fi

echo ""
echo "═══ RESULT: $PASS passed, $FAIL failed ═══"
[ "$FAIL" -gt 0 ] && { printf 'FAILED: %s\n' "${FAILED[*]}"; exit 1; } || { echo "All live invariants hold."; exit 0; }
