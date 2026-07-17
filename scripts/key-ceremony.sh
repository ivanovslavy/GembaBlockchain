#!/usr/bin/env bash
# =============================================================================
# key-ceremony.sh — MAINNET key ceremony, OWNER-machine side.
# (Validator operator keys are born on their boxes — scripts/ceremony-validator-box.sh.)
#
# Generates the 10 operational keys (file keyring, passphrase-protected), records
# every mnemonic ONLY inside a gpg-encrypted file (plaintext is shredded), writes
# the public ADDRESS sheet the genesis builder + deploy scripts consume, makes an
# encrypted backup, and can PROVE the backup restores (the owner's condition:
# every key exists and is usable when needed).
#
#   ./key-ceremony.sh generate      # create the keys + encrypted mnemonics + sheet
#   ./key-ceremony.sh backup        # tar+gpg the whole ceremony dir -> 2 copies
#   ./key-ceremony.sh restore-test  # decrypt the backup, re-list keys, compare sheet
#
# Env: GEMBAD (default /tmp/gembad), CEREMONY_DIR (default ~/gemba-mainnet-ceremony)
# The dir is chmod 700 and MUST be outside any git tree. Run interactively (gpg +
# keyring passphrases). See docs/runbooks/mainnet-genesis-ceremony.md Phase 2 and
# docs/runbooks/key-ceremony-worksheet.md.
# =============================================================================
set -euo pipefail
umask 077

EVMD="${GEMBAD:-/tmp/gembad}"
DIR="${CEREMONY_DIR:-$HOME/gemba-mainnet-ceremony}"
KEYS=(founder foundation dao contingency publicfaucet guardian1 guardian2 guardian3 dispenser-owner collector-recipient)
SHEET="$DIR/ceremony-addresses.env"

die() { echo "FATAL: $*" >&2; exit 1; }
command -v gpg >/dev/null 2>&1 || die "gpg not installed"
command -v jq >/dev/null 2>&1 || die "jq not installed"
[ -x "$EVMD" ] || die "gembad not found at \$GEMBAD=$EVMD (run chain/gembad/build-gembad.sh)"
case "$DIR" in */GembaBlockchain*|*/Documents/Claude*) die "CEREMONY_DIR must be OUTSIDE the repo tree ($DIR)";; esac

# bech32 -> 0x EVM address (same eth_secp256k1 key, two encodings)
to0x() { "$EVMD" keys parse "$1" --output json 2>/dev/null | jq -r '.bytes' | sed 's/^/0x/' | tr 'A-F' 'a-f'; }

generate() {
  [ -e "$DIR/keyring-file" ] && die "$DIR already holds a keyring — refusing to overwrite. Move it away first."
  mkdir -p "$DIR"; chmod 700 "$DIR"
  echo ">> Generating ${#KEYS[@]} keys into the FILE keyring at $DIR (one passphrase, asked once per key)."
  echo ">> Mnemonics go ONLY into mnemonics.gpg — nothing plaintext survives this run."
  MNEM="$(mktemp -p "$DIR" .mnemonics.XXXXXX)"
  trap 'shred -u "$MNEM" 2>/dev/null || rm -f "$MNEM"' EXIT
  for k in "${KEYS[@]}"; do
    echo "---- $k ----"
    "$EVMD" keys add "$k" --keyring-backend file --algo eth_secp256k1 --home "$DIR" --output json >>"$MNEM" 2>&1 \
      || die "keys add $k failed"
    echo >>"$MNEM"
  done
  echo ">> Encrypting the mnemonics (choose a STRONG passphrase — this file IS the network treasury):"
  gpg --symmetric --cipher-algo AES256 --output "$DIR/mnemonics.gpg" "$MNEM"
  shred -u "$MNEM"; trap - EXIT

  echo ">> Writing the public address sheet: $SHEET"
  {
    echo "# Gemba mainnet key ceremony — PUBLIC addresses only (generated $(date -u +%Y-%m-%dT%H:%M:%SZ))"
    echo "# Feed into: init-gembad-mainnet.sh build + DeployGovernance/DeployDispenser envs"
    for k in "${KEYS[@]}"; do
      b32="$("$EVMD" keys show "$k" -a --keyring-backend file --home "$DIR")"
      var="$(echo "$k" | tr 'a-z-' 'A-Z_')"
      echo "${var}_BECH32=$b32"
      echo "${var}_0X=$(to0x "$b32")"
    done
    echo "# Genesis-builder aliases:"
    echo 'FOUNDER_ADDR=$FOUNDER_BECH32; FOUNDATION_ADDR=$FOUNDATION_BECH32; DAO_ADDR=$DAO_BECH32'
    echo 'CONTINGENCY_ADDR=$CONTINGENCY_BECH32; PUBLICFAUCET_ADDR=$PUBLICFAUCET_BECH32'
    echo "# VAL_ADDRS: collected from the 4 validator boxes (ceremony-validator-box.sh prepare)"
    echo "VAL_ADDRS=\"\""
  } >"$SHEET"
  chmod 600 "$SHEET"
  echo ""
  echo ">> DONE. Next: './key-ceremony.sh backup', then './key-ceremony.sh restore-test'."
  echo ">> Private keys for deploy-time envs (FOUNDER_PK etc.) are exported ONLY at the"
  echo ">> moment of use:  $EVMD keys unsafe-export-eth-key <name> --keyring-backend file --home $DIR"
  echo ">> — never store the export; paste into the env of the single command that needs it."
}

backup() {
  [ -f "$SHEET" ] || die "no ceremony at $DIR (run generate first)"
  OUT="$DIR/../gemba-mainnet-keys-$(date +%Y%m%d).tar.gpg"
  tar -C "$DIR" -cf - . | gpg --symmetric --cipher-algo AES256 --output "$OUT"
  chmod 600 "$OUT"
  sha256sum "$OUT"
  echo ">> Backup: $OUT"
  echo ">> Copy it to TWO offline media (USB + second location), verify the sha256 on each,"
  echo ">> then run './key-ceremony.sh restore-test' AGAINST A COPY to prove it restores."
}

restore_test() {
  read -r -p "Path to the .tar.gpg backup copy to test: " BK
  [ -f "$BK" ] || die "no file at $BK"
  T="$(mktemp -d)"; chmod 700 "$T"
  trap 'rm -rf "$T"' EXIT
  gpg --decrypt "$BK" | tar -C "$T" -xf -
  echo ">> Backup decrypts. Comparing every key address against the live keyring:"
  fail=0
  for k in "${KEYS[@]}"; do
    a="$("$EVMD" keys show "$k" -a --keyring-backend file --home "$T" 2>/dev/null || echo RESTORE-FAIL)"
    b="$("$EVMD" keys show "$k" -a --keyring-backend file --home "$DIR" 2>/dev/null || echo LIVE-FAIL)"
    if [ "$a" = "$b" ] && [ "$a" != "RESTORE-FAIL" ]; then echo "  [OK]   $k  $a"
    else echo "  [FAIL] $k  restored=$a live=$b"; fail=1; fi
  done
  [ -f "$T/mnemonics.gpg" ] && echo "  [OK]   mnemonics.gpg present in backup" || { echo "  [FAIL] mnemonics.gpg MISSING from backup"; fail=1; }
  [ "$fail" -eq 0 ] && echo "RESTORE TEST OK — every key restores and matches. Log this output." \
                    || { echo "RESTORE TEST FAILED — do NOT proceed to genesis."; exit 1; }
}

case "${1:-}" in
  generate) generate ;;
  backup) backup ;;
  restore-test) restore_test ;;
  *) echo "usage: $0 {generate|backup|restore-test}"; exit 1 ;;
esac
