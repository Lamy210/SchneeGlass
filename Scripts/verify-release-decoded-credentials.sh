#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Decoded release credential verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 3 ]] \
  || fail "usage: verify-release-decoded-credentials.sh <p12-path> <p12-password> <private-key-path>"

P12_PATH="$1"
P12_PASSWORD="$2"
PRIVATE_KEY_PATH="$3"

[[ -s "$P12_PATH" ]] || fail "PKCS#12 file is missing or empty"
[[ -n "$P12_PASSWORD" ]] || fail "PKCS#12 password is missing"
[[ -s "$PRIVATE_KEY_PATH" ]] || fail "App Store Connect private key file is missing or empty"

echo 'Decoded release credential files are present'
