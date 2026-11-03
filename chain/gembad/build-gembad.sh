#!/usr/bin/env bash
# =============================================================================
# build-gembad.sh — build the `gembad` node binary = pinned cosmos/evm evmd
# (v0.7.4) + three tracked patches + the GembaBlockchain custom modules wired in.
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
# Pinned, known-good (§16.6). v0.7.4 (2026-11-02) carries six security advisories v0.7.3 lacks;
# the live testnet runs v0.7.3 (39daa6e) until the halt-height upgrade in
# docs/runbooks/validator-binary-refresh-2026-10.md. EVM_VERSION=v0.7.3 still builds the old line.
EVM_VERSION="${EVM_VERSION:-v0.7.4}"
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
# From v0.7.4 upstream carries defect 1 itself (GHSA-9xwc-4fgh-f64f: recover() in the same
# insertTxs), so on v0.7.4+ only defect 2, the stale-rechecker guard, is ours to carry.
case "$EVM_VERSION" in
  v0.7.0|v0.7.1|v0.7.2|v0.7.3) MEMPOOL_PATCH=gembad-mempool-fixes.patch ;;          # queue recover + guard
  *)                           MEMPOOL_PATCH=gembad-mempool-recheck-guard.patch ;;  # guard only
esac
echo ">> applying gembad mempool fixes ($MEMPOOL_PATCH)"
git -C "$BUILD_DIR" apply --recount "$HERE/$MEMPOOL_PATCH"

# BLOBBASEFEE (0x4a): cosmos/evm never sets vm.BlockContext.BlobBaseFee, so the Cancun opcode
# pushes a nil *uint256.Int and dereferences it — eth_call answers with a nil-pointer error, and a
# transaction that reaches the opcode panics; baseapp recovers it, so the tx is included as a
# Cosmos-level failure (code 111222, gas_used 0, no EVM receipt — the wallet waits forever). Not fixed upstream through v0.7.4, v1.0.0-rc2 or
# main (checked 2026-11-03). The patch reports a blob base fee of 0, which is what eth_feeHistory
# already says for every block. STATE-MACHINE-BREAKING for any transaction that executes the
# opcode, so it ships only through a coordinated halt-height upgrade (or at genesis).
# See docs/runbooks/validator-binary-refresh-2026-10.md and docs/evm-compatibility.md.
echo ">> applying gembad BLOBBASEFEE fix (BlockContext.BlobBaseFee = 0)"
git -C "$BUILD_DIR" apply --recount "$HERE/gembad-blobbasefee.patch"

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
# The build date is the COMMIT's date (not the wall clock) and -trimpath drops the build directory
# and module-cache paths from the binary. That removes two known sources of drift, but it is NOT
# enough for bit-for-bit reproducibility — measured 2026-11-03: four builds of the same commit with
# the same go1.25.9 gave three different sha256s, differing in .text/.rodata (not in metadata;
# `go version -m` is identical). Until that is tracked down: build ONCE, record that artefact's
# sha256, ship that one file to every box and compare the hash before each swap.
BUILD_DATE="${BUILD_DATE:-$(TZ=UTC git -C "$CHAIN_DIR" log -1 --format=%cd --date=format-local:%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)}"
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
go build -trimpath -ldflags "$LDFLAGS" -o "$OUT" ./cmd/evmd
sha256sum "$OUT"
echo "OK: $OUT (version ${GEMBAD_VERSION}, commit ${GEMBAD_COMMIT})"
"$OUT" version 2>/dev/null || true
