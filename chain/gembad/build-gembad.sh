#!/usr/bin/env bash
# =============================================================================
# build-gembad.sh — build the `gembad` node binary = pinned cosmos/evm evmd
# (v0.7.0) + the GembaBlockchain Phase 2 custom modules wired in.
#
# We do NOT vendor evmd into the repo. Instead we fetch the pinned reference app
# at build time (as in Phase 1) and apply a small, version-pinned wiring patch
# (gembad-wiring.patch: app.go + permissions.go only). The custom modules stay
# isolated in chain/x and are pulled in via a go.mod replace, so an upstream bump
# is just: re-clone the new tag, re-apply/refresh the patch (CLAUDE.md §16.6).
#
# Output: $OUT (default /tmp/gembad).
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAIN_DIR="$(cd "$HERE/.." && pwd)"          # the chain Go module (has go.mod)
EVM_VERSION="${EVM_VERSION:-v0.7.0}"          # pinned, known-good (§16.6)
BUILD_DIR="${BUILD_DIR:-/tmp/gembad-build}"
OUT="${OUT:-/tmp/gembad}"

command -v go >/dev/null 2>&1 || { echo "FATAL: go not installed"; exit 1; }

echo ">> fetching cosmos/evm $EVM_VERSION into $BUILD_DIR"
rm -rf "$BUILD_DIR"
git clone -q --depth 1 --branch "$EVM_VERSION" https://github.com/cosmos/evm "$BUILD_DIR"

echo ">> applying gembad wiring patch (evmd/app.go + evmd/config/permissions.go)"
git -C "$BUILD_DIR" apply "$HERE/gembad-wiring.patch"

echo ">> pointing evmd at the local gemba chain module ($CHAIN_DIR)"
cd "$BUILD_DIR/evmd"
go mod edit -require=github.com/ivanovslavy/GembaBlockchain/chain@v0.0.0
go mod edit -replace=github.com/ivanovslavy/GembaBlockchain/chain="$CHAIN_DIR"
go mod tidy >/dev/null 2>&1

echo ">> building gembad -> $OUT"
go build -o "$OUT" ./cmd/evmd
echo "OK: $OUT"
"$OUT" version 2>/dev/null || true
