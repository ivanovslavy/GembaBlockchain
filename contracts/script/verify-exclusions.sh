#!/usr/bin/env bash
# =============================================================================
# verify-exclusions.sh — post-deploy check of the GembaVotes exclusion set
# ("only validators vote at launch" — docs/mainnet-exclusion-list.md).
#
#   VOTES=0x<GembaVotes> RPC=<json-rpc url> LIST=<file: one 0x address per line> \
#     ./verify-exclusions.sh
#
# Asserts for EVERY address in LIST: excluded(addr)==true AND getVotes(addr)==0,
# plus a negative control (a fresh address must NOT be excluded — the wrapper
# stays permissionless). Exit 0 only if everything holds. Record the output.
# =============================================================================
set -euo pipefail
: "${VOTES:?set VOTES=0x<GembaVotes address>}"
: "${RPC:?set RPC=<json-rpc url>}"
: "${LIST:?set LIST=<file with one 0x address per line>}"
command -v cast >/dev/null 2>&1 || { echo "FATAL: foundry 'cast' not installed"; exit 1; }
[ -s "$LIST" ] || { echo "FATAL: LIST file $LIST is empty"; exit 1; }

fail=0; n=0
while IFS= read -r addr; do
  addr="$(echo "$addr" | tr -d '[:space:]')"; [ -z "$addr" ] && continue
  case "$addr" in \#*) continue ;; esac
  n=$((n+1))
  ex="$(cast call "$VOTES" 'excluded(address)(bool)' "$addr" --rpc-url "$RPC")"
  votes="$(cast call "$VOTES" 'getVotes(address)(uint256)' "$addr" --rpc-url "$RPC")"; votes="${votes%% *}"
  if [ "$ex" = "true" ] && [ "$votes" = "0" ]; then
    echo "  [OK]   $addr  excluded=true getVotes=0"
  else
    echo "  [FAIL] $addr  excluded=$ex getVotes=$votes  (must be true / 0)"
    fail=1
  fi
done < "$LIST"

# negative control: a fresh random address must NOT be excluded (permissionless wrapper)
CONTROL="0x000000000000000000000000000000000000dEaD"
exc="$(cast call "$VOTES" 'excluded(address)(bool)' "$CONTROL" --rpc-url "$RPC")"
if [ "$exc" = "false" ]; then
  echo "  [OK]   negative control $CONTROL excluded=false (wrapper stays open to the public)"
else
  echo "  [FAIL] negative control $CONTROL excluded=$exc — exclusion is over-broad!"
  fail=1
fi

echo ""
if [ "$fail" -ne 0 ]; then echo "EXCLUSION VERIFY FAILED — DO NOT ANNOUNCE LAUNCH."; exit 1; fi
echo "EXCLUSION VERIFY OK — $n address(es) excluded with zero votes; control address open."
