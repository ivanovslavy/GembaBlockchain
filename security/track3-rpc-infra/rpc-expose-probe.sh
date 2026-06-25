#!/usr/bin/env bash
# Track 3 — JSON-RPC method-exposure probe (NON-DESTRUCTIVE, read-only).
# Confirms dangerous methods (admin/personal/txpool/miner/debug) are disabled on
# public RPCs. See docs/security-pentest-2026-06-24.md P-2/P-3.
set -u
ENDPOINTS=("https://testnet.gembascan.io/rpc" "https://rpc1.gembascan.io" "https://rpc2.gembascan.io")
DANGEROUS=(admin_nodeInfo personal_listAccounts txpool_content miner_setEtherbase debug_traceBlockByNumber)

probe() { # url method [params]
  curl -s --max-time 8 -X POST "$1" -H 'Content-Type: application/json' \
    --data "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$2\",\"params\":${3:-[]}}" 2>/dev/null | head -c 200; echo
}

for url in "${ENDPOINTS[@]}"; do
  echo "──────── $url ────────"
  printf "  chainId      : "; probe "$url" eth_chainId
  printf "  blockNumber  : "; probe "$url" eth_blockNumber
  printf "  clientVer    : "; probe "$url" web3_clientVersion
  echo "  -- DANGEROUS (want: 'does not exist/is not available') --"
  for m in "${DANGEROUS[@]}"; do printf "  %-26s : " "$m"; probe "$url" "$m" '["0x1",{}]'; done
done
