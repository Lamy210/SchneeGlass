#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release secret environment lifecycle validation failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <build-script-path>"
SCRIPT="$1"
[[ -f "$SCRIPT" ]] || fail "build script is missing: $SCRIPT"

line_of_exact() {
  local path="$1"
  local expected="$2"
  local result=''
  local status=0

  set +e
  result="$(awk -v expected="$expected" '
    $0 == expected {
      count += 1
      line = NR
    }
    END {
      if (count != 1) {
        exit 42
      }
      print line
    }
  ' "$path")"
  status=$?
  set -e

  [[ "$status" -eq 0 ]]     || fail "expected workflow line exactly once: $expected"
  [[ "$result" =~ ^[1-9][0-9]*$ ]]     || fail "line number is invalid for: $expected"

  printf '%s\n' "$result"
}

CLEANUP_CLEAR_LINE="$(line_of_exact "$SCRIPT" '  unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64')"
CLEANUP_SECURITY_LINE="$(line_of_exact "$SCRIPT" '    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1')"
DECODE_P12_LINE="$(line_of_exact "$SCRIPT" 'printf '"'"'%s'"'"' "$DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D > "$P12_PATH"')"
DECODE_API_KEY_LINE="$(line_of_exact "$SCRIPT" 'printf '"'"'%s'"'"' "$APPSTORE_CONNECT_PRIVATE_KEY_BASE64" | /usr/bin/base64 -D > "$API_KEY_PATH"')"
CLEAR_ENCODED_LINE="$(line_of_exact "$SCRIPT" 'unset DEVELOPER_ID_P12_BASE64 APPSTORE_CONNECT_PRIVATE_KEY_BASE64')"
VERIFY_DECODED_LINE="$(line_of_exact "$SCRIPT" 'bash Scripts/verify-release-decoded-credentials.sh \')"
IMPORT_P12_LINE="$(line_of_exact "$SCRIPT" 'security import "$P12_PATH" \')"
CLEAR_PASSWORD_LINE="$(line_of_exact "$SCRIPT" 'unset DEVELOPER_ID_P12_PASSWORD')"
PARTITION_LIST_LINE="$(line_of_exact "$SCRIPT" 'security set-key-partition-list \')"

(( CLEANUP_CLEAR_LINE < CLEANUP_SECURITY_LINE ))   || fail "cleanup must clear signing secrets before invoking cleanup subprocesses"
(( DECODE_P12_LINE < CLEAR_ENCODED_LINE ))   || fail "encoded Developer ID secret must be cleared after PKCS#12 decode"
(( DECODE_API_KEY_LINE < CLEAR_ENCODED_LINE ))   || fail "encoded App Store Connect secret must be cleared after private-key decode"
(( CLEAR_ENCODED_LINE < VERIFY_DECODED_LINE ))   || fail "encoded credential secrets must be cleared before decoded credential verification"
(( VERIFY_DECODED_LINE < IMPORT_P12_LINE ))   || fail "decoded credential verification must happen before PKCS#12 import"
(( IMPORT_P12_LINE < CLEAR_PASSWORD_LINE ))   || fail "PKCS#12 password must remain available through security import"
(( CLEAR_PASSWORD_LINE < PARTITION_LIST_LINE ))   || fail "PKCS#12 password must be cleared before later keychain/signing subprocesses"

echo 'Release secret environment lifecycle verified'
