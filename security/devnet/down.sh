#!/usr/bin/env bash
# security/devnet/down.sh — stop the throwaway devnet (kill only its gembad procs by home).
BASE="${BASE:-$HOME/.gembad-sec-devnet}"
pkill -9 -f "gembad start --home $BASE" 2>/dev/null && echo "stopped devnet ($BASE)" || echo "no devnet procs for $BASE"
[ "${1:-}" = "--wipe" ] && { rm -rf "$BASE"; echo "wiped $BASE"; }
