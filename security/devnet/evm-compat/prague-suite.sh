#!/usr/bin/env bash
# =============================================================================
# prague-suite.sh — what the gembad EVM actually does with Cancun's BLOBBASEFEE and with Prague
# (EIP-7702 SetCode, EIP-2537 BLS12-381, EIP-2935, EIP-7623) — measured on a node, not assumed.
#
# DEVNET ONLY. It sends transactions and needs two FUNDED throwaway keys. Never point it at the
# live testnet: test T1 is the very eth_call that answers with a nil-pointer error on 39daa6e.
#
#   RPC=http://127.0.0.1:8545 PK=<sponsor hex key> PK2=<authority hex key> ./prague-suite.sh
#
# Every line is PASS / FAIL / INFO with the raw value that decided it, so a reader can check the
# verdict instead of trusting it. Exit code = number of FAILs.
# =============================================================================
set -uo pipefail
RPC=${RPC:-http://127.0.0.1:8545}
PK=${PK:?set PK (funded devnet key, hex)}; PK2=${PK2:?set PK2 (second funded devnet key, hex)}
case "$PK" in 0x*) ;; *) PK=0x$PK ;; esac; case "$PK2" in 0x*) ;; *) PK2=0x$PK2 ;; esac
GAS_PRICE=${GAS_PRICE:-10000000000}     # 10 gwei: above the 5 gwei floor and the devnet base fee
FAILS=0
pass(){ echo "PASS  $*"; }
fail(){ echo "FAIL  $*"; FAILS=$((FAILS+1)); }
info(){ echo "INFO  $*"; }
rpc(){ curl -s --max-time 20 -X POST -H 'content-type: application/json' --data "$1" "$RPC"; }
# eth_call of raw INIT code (no "to"): the EVM runs it as a creation and returns what it RETURNs —
# so an opcode can be probed without deploying anything.
probe(){ rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"data\":\"$1\"},\"latest\"]}"; }
call_to(){ rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_call\",\"params\":[{\"to\":\"$1\",\"data\":\"$2\"},\"latest\"]}"; }
res(){ jq -r '.result // ("ERROR: " + (.error.message // "no answer"))'; }
# send GASLIMIT <cast send args…> — options go BEFORE the args: `--create` is a cast subcommand.
send(){ local g=$1; shift; cast send --rpc-url "$RPC" --private-key "$PK" --gas-price "$GAS_PRICE" --gas-limit "$g" --timeout "${TX_TIMEOUT:-30}" --json "$@" 2>&1; }
ME=$(cast wallet address --private-key "$PK"); AUTH=$(cast wallet address --private-key "$PK2")
CHAIN=$(cast chain-id --rpc-url "$RPC")
echo "== prague-suite against $RPC (chainId $CHAIN) · client $(rpc '{"jsonrpc":"2.0","id":1,"method":"web3_clientVersion","params":[]}' | res)"
[ "$CHAIN" = "821207" ] && { echo "REFUSING: 821207 is the LIVE testnet. Devnet only."; exit 99; }
Z32=0000000000000000000000000000000000000000000000000000000000000000

# --- T1 BLOBBASEFEE (0x4a) through eth_call ---------------------------------------------------------
r=$(probe 0x4a5f5260205ff3 | res)
case "$r" in ERROR*) fail "T1 BLOBBASEFEE via eth_call → $r" ;; 0x$Z32) pass "T1 BLOBBASEFEE via eth_call → 0 ($r)" ;; *) info "T1 BLOBBASEFEE via eth_call → $r" ;; esac

# --- T2 BLOBBASEFEE inside a TRANSACTION (consensus path) --------------------------------------------
# init code: BLOBBASEFEE PUSH0 SSTORE STOP — stores the value in the new contract's slot 0.
# Fixed gas limit: on a node with the defect eth_estimateGas would itself fail.
b0=$(cast balance --rpc-url "$RPC" "$ME"); n0=$(cast nonce --rpc-url "$RPC" "$ME")
out=$(send 100000 --create 0x4a5f5500)
b1=$(cast balance --rpc-url "$RPC" "$ME"); n1=$(cast nonce --rpc-url "$RPC" "$ME")
info "T2 sender paid $(python3 -c "print(($b0-$b1)//$GAS_PRICE)") gas-units worth of fee (limit 100000), nonce $n0 → $n1"   # balances exceed int64: python, not $(( ))
st=$(echo "$out" | jq -r '.status // empty' 2>/dev/null); ca=$(echo "$out" | jq -r '.contractAddress // empty' 2>/dev/null)
gu=$(echo "$out" | jq -r '.gasUsed // empty' 2>/dev/null); tx=$(echo "$out" | jq -r '.transactionHash // empty' 2>/dev/null)
if [ "$st" = "0x1" ]; then
  slot=$(cast storage --rpc-url "$RPC" "$ca" 0 2>&1)
  pass "T2 BLOBBASEFEE in a tx → status 1, gasUsed $((gu)), stored slot0=$slot (tx $tx)"
elif [ -n "$st" ]; then
  fail "T2 BLOBBASEFEE in a tx → status $st, gasUsed $((gu)) of 100000 (tx $tx)"
else
  # No receipt. On 39daa6e the tx IS in a block, but as a Cosmos-level failure the EVM indexer
  # never turns into a receipt: code 111222 (baseapp ErrPanic), gas_used 0. Wallets wait forever.
  fail "T2 BLOBBASEFEE in a tx → no EVM receipt ($(echo "$out" | tail -1 | cut -c1-120)); look for code 111222 in block_results"
fi

# --- T3 the rest of Cancun, for contrast ---------------------------------------------------------------
r=$(probe 0x602a5f5d5f5c5f5260205ff3 | res)                       # TSTORE 42 at key 0, TLOAD it back
[ "$r" = "0x$(printf '%064x' 42)" ] && pass "T3a TSTORE/TLOAD → 42" || fail "T3a TSTORE/TLOAD → $r"
r=$(probe 0x602a5f5260205f60205e60206020f3 | res)                 # MSTORE 42, MCOPY 0→0x20, return 0x20
[ "$r" = "0x$(printf '%064x' 42)" ] && pass "T3b MCOPY → 42" || fail "T3b MCOPY → $r"
r=$(probe 0x5f495f5260205ff3 | res)                               # BLOBHASH(0) with no blobs
[ "$r" = "0x$Z32" ] && pass "T3c BLOBHASH(0) → 0" || fail "T3c BLOBHASH(0) → $r"
r=$(probe 0x485f5260205ff3 | res)                                 # BASEFEE
case "$r" in ERROR*) fail "T3d BASEFEE → $r" ;; *) pass "T3d BASEFEE → $((r)) wei" ;; esac

# --- T4 EIP-7702: type-4 SetCode transaction ------------------------------------------------------------
# Delegate runtime: TIMESTAMP PUSH0 SSTORE (write slot 0 of whoever runs it), then return ADDRESS.
# Run through a delegated EOA it must write the EOA's OWN storage and report the EOA as ADDRESS.
RUNTIME=425f55305f5260205ff3; LEN=$(printf '%02x' $(( ${#RUNTIME} / 2 )))
INIT=0x60${LEN}600a5f3960${LEN}5ff3${RUNTIME}                       # CODECOPY runtime, RETURN it
out=$(send 200000 --create "$INIT"); DEL=$(echo "$out" | jq -r '.contractAddress // empty' 2>/dev/null)
if [ -z "$DEL" ] || [ "$(cast code --rpc-url "$RPC" "$DEL")" != "0x$RUNTIME" ]; then
  fail "T4 could not deploy the delegate contract: $(echo "$out" | tail -1 | cut -c1-200)"
else
  info "T4 delegate contract $DEL, authority EOA $AUTH, sponsor $ME"
  n=$(cast nonce --rpc-url "$RPC" "$AUTH")
  sa=$(cast wallet sign-auth "$DEL" --private-key "$PK2" --nonce "$n" --chain "$CHAIN" --rpc-url "$RPC" 2>&1)
  case "$sa" in 0x*) ;; *) fail "T4a cast could not sign the authorization: $sa"; sa="" ;; esac
  if [ -n "$sa" ]; then
    out=$(send 200000 --auth "$sa" "$AUTH")
    st=$(echo "$out" | jq -r '.status // empty' 2>/dev/null); ty=$(echo "$out" | jq -r '.type // empty' 2>/dev/null)
    code=$(cast code --rpc-url "$RPC" "$AUTH" 2>&1)
    want="0xef0100$(echo "${DEL#0x}" | tr 'A-F' 'a-f')"
    if [ "$st" = "0x1" ] && [ "$code" = "$want" ]; then
      pass "T4a type-$((ty)) SetCode tx included; authority code = $code (EIP-7702 designator)"
    else
      fail "T4a SetCode tx → status '${st:-none}' type '${ty:-?}', authority code '$code' (want $want) $(echo "$out" | tail -1 | cut -c1-160)"
    fi
    r=$(call_to "$AUTH" 0x | res)
    a=$(echo "${AUTH#0x}" | tr 'A-F' 'a-f')
    [ "$r" = "0x000000000000000000000000$a" ] && pass "T4b eth_call to the delegated EOA runs the delegate code, ADDRESS = the EOA" \
                                            || fail "T4b eth_call to the delegated EOA → $r"
    out=$(send 100000 "$AUTH"); st=$(echo "$out" | jq -r '.status // empty' 2>/dev/null)
    s0=$(cast storage --rpc-url "$RPC" "$AUTH" 0 2>&1)
    [ "$st" = "0x1" ] && [ "$s0" != "0x$Z32" ] && pass "T4c a tx to the delegated EOA writes the EOA's own storage (slot0 = $((s0)), a timestamp)" \
                                               || fail "T4c tx to the delegated EOA → status '$st', slot0 $s0"
    n=$(cast nonce --rpc-url "$RPC" "$AUTH")
    sa=$(cast wallet sign-auth 0x0000000000000000000000000000000000000000 --private-key "$PK2" --nonce "$n" --chain "$CHAIN" --rpc-url "$RPC" 2>&1)
    out=$(send 200000 --auth "$sa" "$AUTH"); st=$(echo "$out" | jq -r '.status // empty' 2>/dev/null)
    code=$(cast code --rpc-url "$RPC" "$AUTH" 2>&1)
    [ "$st" = "0x1" ] && [ "$code" = "0x" ] && pass "T4d delegation to address(0) clears it (code back to 0x)" \
                                           || fail "T4d clearing the delegation → status '$st', code '$code'"
    # The authority can still send ordinary transactions afterwards (its nonce was bumped by each auth).
    out=$(cast send --rpc-url "$RPC" --private-key "$PK2" --gas-price "$GAS_PRICE" --json "$ME" --value 1 2>&1)
    st=$(echo "$out" | jq -r '.status // empty' 2>/dev/null)
    [ "$st" = "0x1" ] && pass "T4e the former authority sends a normal tx afterwards" || fail "T4e authority tx afterwards → $(echo "$out" | tail -1 | cut -c1-160)"
  fi
fi

# --- T5 EIP-2537 BLS12-381 precompiles --------------------------------------------------------------------
ZERO256=$(printf '0%.0s' $(seq 1 512))
r=$(call_to 0x000000000000000000000000000000000000000b 0x$ZERO256 | res)   # G1ADD(∞, ∞) = ∞
[ "$r" = "0x$(printf '0%.0s' $(seq 1 256))" ] && pass "T5 EIP-2537 G1ADD (0x0b) present: ∞+∞ = 128 zero bytes" \
                                              || fail "T5 EIP-2537 G1ADD (0x0b) → ${r:0:80}"

# --- T6 EIP-2935 historical block-hash system contract -------------------------------------------------------
H2935=0x0000F90827F1C53a10cb7A02335B175320002935
c=$(cast code --rpc-url "$RPC" "$H2935" 2>&1)
if [ "$c" = "0x" ]; then info "T6 EIP-2935 history contract NOT deployed at $H2935 (BLOCKHASH opcode is served by the keeper instead)"
else info "T6 EIP-2935 history contract has code (${#c} hex chars)"; fi
bn=$(cast block-number --rpc-url "$RPC"); prev=$((bn-2))
r=$(probe 0x$(printf '7f%064x' "$prev")405f5260205ff3 | res)        # PUSH32 n, BLOCKHASH, return it
want=$(cast block --rpc-url "$RPC" "$prev" --field hash 2>/dev/null)
[ "$r" = "$want" ] && pass "T6 BLOCKHASH(n-2) matches eth_getBlockByNumber hash" || info "T6 BLOCKHASH(n-2) = $r · block hash = $want (CometBFT vs EVM hash domains may differ)"

# --- T7 EIP-7623 calldata floor ------------------------------------------------------------------------------
DATA=0x$(printf 'ff%.0s' $(seq 1 1000))
g=$(cast estimate --rpc-url "$RPC" --from "$ME" "$AUTH" "$DATA" 2>&1 || true)
case "$g" in
  61000) pass "T7 EIP-7623 floor active: 1000 non-zero calldata bytes to an EOA estimate $g (pre-Prague 37000)";;
  37000) info "T7 EIP-7623 floor NOT active: estimate $g (pre-Prague pricing)";;
  *)     info "T7 calldata estimate for 1000 non-zero bytes = $g";;
esac

# --- T8 Osaka is not scheduled: CLZ (0x1e) must be an invalid opcode ------------------------------------------
r=$(probe 0x60011e5f5260205ff3 | res)
case "$r" in ERROR*) info "T8 CLZ (Osaka) not active, as configured (OsakaTime nil): $r" ;; *) info "T8 CLZ returned $r — Osaka opcodes ARE active" ;; esac

echo "== done: $FAILS FAIL(s)"
exit "$FAILS"
