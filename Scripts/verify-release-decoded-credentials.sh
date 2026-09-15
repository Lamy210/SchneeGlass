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
