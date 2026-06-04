#!/usr/bin/env bash
# =============================================================================
# setup-libs.sh — fetch pinned Solidity dependencies into lib/ (git-ignored).
# Consistent with the project's "fetch pinned deps at build time, don't vendor"
# pattern (cf. chain/gembad/build-gembad.sh). Run once before `forge build/test`.
# =============================================================================
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OZ_VERSION="${OZ_VERSION:-v5.1.0}"   # pinned, known-good OpenZeppelin v5
mkdir -p "$HERE/lib"

clone() { # repo, dir
  local dir="$HERE/lib/$2"
  if [ -d "$dir/.git" ]; then echo ">> $2 already present"; return; fi
  rm -rf "$dir"
  git clone -q --depth 1 --branch "$OZ_VERSION" "https://github.com/OpenZeppelin/$1" "$dir"
  echo ">> $2 @ $OZ_VERSION"
}

clone openzeppelin-contracts             openzeppelin-contracts
clone openzeppelin-contracts-upgradeable openzeppelin-contracts-upgradeable

# forge-std for tests (separate pin)
if [ ! -d "$HERE/lib/forge-std/.git" ]; then
  rm -rf "$HERE/lib/forge-std"
  git clone -q --depth 1 --branch "${FORGE_STD_VERSION:-v1.9.4}" https://github.com/foundry-rs/forge-std "$HERE/lib/forge-std"
  echo ">> forge-std @ ${FORGE_STD_VERSION:-v1.9.4}"
fi
echo "OK. Dependencies in contracts/lib (see remappings.txt)."
