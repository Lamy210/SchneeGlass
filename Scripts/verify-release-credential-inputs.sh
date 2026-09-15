#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release credential input verification failed: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "required release environment value is missing: $name"
}

for name in \
  RELEASE_VERSION \
  DEVELOPER_ID_P12_BASE64 \
  DEVELOPER_ID_P12_PASSWORD \
  APPLE_TEAM_ID \
  APPSTORE_CONNECT_KEY_ID \
  APPSTORE_CONNECT_ISSUER_ID \
  APPSTORE_CONNECT_PRIVATE_KEY_BASE64; do
  require_env "$name"
done

echo 'Release credential inputs are present'
