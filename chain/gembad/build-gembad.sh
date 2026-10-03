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
EVM_VERSION="${EVM_VERSION:-v0.7.3}"          # pinned, known-good (§16.6)
BUILD_DIR="${BUILD_DIR:-/tmp/gembad-build}"
OUT="${OUT:-/tmp/gembad}"

command -v go >/dev/null 2>&1 || { echo "FATAL: go not installed"; exit 1; }

echo ">> fetching cosmos/evm $EVM_VERSION into $BUILD_DIR"
rm -rf "$BUILD_DIR"
git clone -q --depth 1 --branch "$EVM_VERSION" https://github.com/cosmos/evm "$BUILD_DIR"

echo ">> applying gembad wiring patch (evmd/app.go + evmd/config/permissions.go)"
git -C "$BUILD_DIR" apply --recount "$HERE/gembad-wiring.patch"

# Two defects in the pinned upstream mempool, both found the hard way on the live testnet on
# 2026-10-03 and neither fixed upstream through v0.7.3 (queue.go is byte-identical from v0.7.0,
# and v1.0.0-rc moves the package wholesale). They are carried as a TRACKED patch rather than
# an uncommitted edit, which is how the irreproducible d8a454f-dirty binary came about:
#   1. mempool/internal/queue — the worker goroutine started by New() has no recover(), so a
#      panic inside the application's ante handler kills the node. One did: a nil AuthInfo.Fee
#      reaching x/auth/ante.SetUpContextDecorator SIGSEGV'd validator .83.
#   2. mempool/recheck_pool.go — RecheckMempool.Insert judges new transactions against the
#      rechecker's long-lived cached context and writes the ante's state changes back into it.
#      That cache rolls over only when doRecheck calls Update on a new head, which returns
#      silently if GetLatestContext fails. When it stopped, .83 answered "§6: 50 GMB already
#      added today" with the day frozen at its last successful bond — for thirteen days, while
#      every other node accepted the same transaction. Now it refreshes instead of trusting it.
# See docs/runbooks/validator-binary-refresh-2026-10.md.
echo ">> applying gembad mempool fixes (queue recover + stale-rechecker guard)"
git -C "$BUILD_DIR" apply --recount "$HERE/gembad-mempool-fixes.patch"

echo ">> pointing evmd at the local gemba chain module ($CHAIN_DIR)"
cd "$BUILD_DIR/evmd"
go mod edit -require=github.com/ivanovslavy/GembaBlockchain/chain@v0.0.0
go mod edit -replace=github.com/ivanovslavy/GembaBlockchain/chain="$CHAIN_DIR"
go mod tidy >/dev/null 2>&1

echo ">> building gembad -> $OUT"
# Stamp a real version (pentest P-3): an unstamped build reports web3_clientVersion
# "Version dev ()", which fingerprints the node. Set a concrete version/commit and
# strip debug info (-s -w) so the binary advertises a controlled string.
#
# NOTE: web3_clientVersion does NOT read the cosmos-sdk version vars — it calls
# github.com/cosmos/evm/version.Version() (AppVersion defaults to "dev"). So we must
# stamp BOTH the cosmos-sdk version pkg (`gembad version`) AND the cosmos/evm version
# pkg (the EVM JSON-RPC web3_clientVersion). Stamping only the SDK pkg leaves the RPC
# advertising "Version dev ()" — exactly the P-3 leak.
GEMBAD_VERSION="${GEMBAD_VERSION:-$(git -C "$CHAIN_DIR" describe --tags --always --dirty 2>/dev/null || echo "v0.1.0")}"
GEMBAD_COMMIT="${GEMBAD_COMMIT:-$(git -C "$CHAIN_DIR" rev-parse --short HEAD 2>/dev/null || echo none)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
SDK_VER="github.com/cosmos/cosmos-sdk/version"
EVM_VER="github.com/cosmos/evm/version"
LDFLAGS="-s -w \
  -X ${SDK_VER}.Name=gemba \
  -X ${SDK_VER}.AppName=gembad \
  -X ${SDK_VER}.Version=${GEMBAD_VERSION} \
  -X ${SDK_VER}.Commit=${GEMBAD_COMMIT} \
  -X ${EVM_VER}.AppVersion=${GEMBAD_VERSION} \
  -X ${EVM_VER}.GitCommit=${GEMBAD_COMMIT} \
  -X ${EVM_VER}.BuildDate=${BUILD_DATE}"
go build -ldflags "$LDFLAGS" -o "$OUT" ./cmd/evmd
echo "OK: $OUT (version ${GEMBAD_VERSION}, commit ${GEMBAD_COMMIT})"
"$OUT" version 2>/dev/null || true
