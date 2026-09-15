#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Decoded release credential verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 2 ]] \
  || fail "usage: verify-release-decoded-credentials.sh <p12-path> <private-key-path>"

P12_PATH="$1"
PRIVATE_KEY_PATH="$2"
P12_PASSWORD="${DEVELOPER_ID_P12_PASSWORD:-}"

[[ -s "$P12_PATH" ]] || fail "PKCS#12 file is missing or empty"
[[ -n "$P12_PASSWORD" ]] || fail "DEVELOPER_ID_P12_PASSWORD is missing"
[[ -s "$PRIVATE_KEY_PATH" ]] || fail "App Store Connect private key file is missing or empty"

SCHNEEGLASS_P12_PASSWORD="$P12_PASSWORD" \
  openssl pkcs12 \
    -in "$P12_PATH" \
    -passin env:SCHNEEGLASS_P12_PASSWORD \
    -noout >/dev/null 2>&1 \
  || fail "PKCS#12 payload or password is invalid"

openssl pkey \
  -in "$PRIVATE_KEY_PATH" \
  -noout >/dev/null 2>&1 \
  || fail "App Store Connect private key payload is invalid"

echo 'Decoded release credentials verified'
