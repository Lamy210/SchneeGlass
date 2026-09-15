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

validate_base64_nonempty() {
  local name="$1"
  local value="${!name}"
  local decoded_size

  if ! decoded_size="$(
    printf '%s' "$value" \
      | /usr/bin/base64 -D 2>/dev/null \
      | wc -c \
      | tr -d '[:space:]'
  )"; then
    fail "$name must be valid base64"
  fi

  [[ "$decoded_size" =~ ^[0-9]+$ ]] \
    || fail "unable to determine decoded size for $name"
  ((decoded_size > 0)) \
    || fail "$name must decode to non-empty data"
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

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "RELEASE_VERSION must be X.Y.Z"
[[ "$APPLE_TEAM_ID" =~ ^[A-Za-z0-9]{10}$ ]] \
  || fail "APPLE_TEAM_ID must be a 10-character ASCII alphanumeric Team ID"
[[ "$APPSTORE_CONNECT_KEY_ID" =~ ^[A-Za-z0-9]{10}$ ]] \
  || fail "APPSTORE_CONNECT_KEY_ID must be a 10-character ASCII alphanumeric key ID"
[[ "$APPSTORE_CONNECT_ISSUER_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
  || fail "APPSTORE_CONNECT_ISSUER_ID must be a UUID"

validate_base64_nonempty DEVELOPER_ID_P12_BASE64
validate_base64_nonempty APPSTORE_CONNECT_PRIVATE_KEY_BASE64

echo 'Release credential inputs verified'
