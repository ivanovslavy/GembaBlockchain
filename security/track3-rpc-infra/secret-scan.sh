#!/usr/bin/env bash
# Track 3 — secret hygiene scan (working tree + git history). NON-DESTRUCTIVE.
# Surfaces hardcoded mnemonics / private keys before the repo goes public.
# Found P-1: a live ~2M-GMB account key derivable from a repo-hardcoded mnemonic.
# See docs/security-pentest-2026-06-24.md.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1

echo "== .env tracked? (want: not) =="
git ls-files | grep -E '(^|/)\.env$' && echo "  !! .env IS TRACKED" || echo "  OK"

echo "== hardcoded BIP-39 mnemonics (12+ words) in tracked files =="
git grep -nIE '\b([a-z]+ ){11,}[a-z]+\b' -- '*.sh' '*.js' '*.go' '*.json' '*.ts' '*.sol' 2>/dev/null \
  | grep -viE '(^[^:]+:[0-9]+: *(#|//|\*))' | grep -viE '(example|lorem|test\()'

echo "== 64-hex private keys in tracked non-test files =="
git grep -nIE '0x[a-fA-F0-9]{64}' -- '*.sh' '*.go' '*.js' '*.ts' 2>/dev/null \
  | grep -viE '(test|demo|stress|example|0x0{64}|PERMIT|TYPEHASH|HASH|hash|salt|0xff)'

echo "== wallet-backup/ perms (want: 0700) =="
stat -c '  %A %a %n' wallet-backup 2>/dev/null || echo "  (none)"

echo "== OPTIONAL: derive addresses from any hardcoded mnemonics and check LIVE balances =="
echo "   (manual: cast wallet address --mnemonic \"<m>\"  then eth_getBalance on the RPC)"
