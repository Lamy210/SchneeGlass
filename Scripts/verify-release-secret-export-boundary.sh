#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release secret export boundary validation failed: $*" >&2
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

  [[ "$status" -eq 0 ]]     || fail "expected script line exactly once: $expected"
  [[ "$result" =~ ^[1-9][0-9]*$ ]]     || fail "line number is invalid for: $expected"

  printf '%s\n' "$result"
}

CAPTURE_P12_LINE="$(line_of_exact "$SCRIPT" 'SIGNING_DEVELOPER_ID_P12_BASE64="${DEVELOPER_ID_P12_BASE64:-}"')"
CAPTURE_PASSWORD_LINE="$(line_of_exact "$SCRIPT" 'SIGNING_DEVELOPER_ID_P12_PASSWORD="${DEVELOPER_ID_P12_PASSWORD:-}"')"
CAPTURE_API_KEY_LINE="$(line_of_exact "$SCRIPT" 'SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64="${APPSTORE_CONNECT_PRIVATE_KEY_BASE64:-}"')"
PRIVATE_EXPORT_CLEAR_LINE="$(line_of_exact "$SCRIPT" 'export -n SIGNING_DEVELOPER_ID_P12_BASE64 SIGNING_DEVELOPER_ID_P12_PASSWORD SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64')"
CLEAR_EXPORTED_LINE="$(line_of_exact "$SCRIPT" 'unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64')"
ROOT_LINE="$(line_of_exact "$SCRIPT" 'ROOT="$(git rev-parse --show-toplevel)"')"

SCOPED_P12_LINE="$(line_of_exact "$SCRIPT" 'DEVELOPER_ID_P12_BASE64="$SIGNING_DEVELOPER_ID_P12_BASE64" \')"
SCOPED_PASSWORD_LINE="$(line_of_exact "$SCRIPT" '  DEVELOPER_ID_P12_PASSWORD="$SIGNING_DEVELOPER_ID_P12_PASSWORD" \')"
SCOPED_API_KEY_LINE="$(line_of_exact "$SCRIPT" '  APPSTORE_CONNECT_PRIVATE_KEY_BASE64="$SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64" \')"
VERIFY_INPUT_LINE="$(line_of_exact "$SCRIPT" '  bash Scripts/verify-release-credential-inputs.sh')"

DECODE_P12_LINE="$(line_of_exact "$SCRIPT" 'printf '"'"'%s'"'"' "$SIGNING_DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D > "$P12_PATH"')"
DECODE_API_KEY_LINE="$(line_of_exact "$SCRIPT" 'printf '"'"'%s'"'"' "$SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64" | /usr/bin/base64 -D > "$API_KEY_PATH"')"
CLEAR_PRIVATE_ENCODED_LINE="$(line_of_exact "$SCRIPT" 'unset SIGNING_DEVELOPER_ID_P12_BASE64 SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64')"
VERIFY_DECODED_PASSWORD_LINE="$(line_of_exact "$SCRIPT" '  "$SIGNING_DEVELOPER_ID_P12_PASSWORD" \')"
IMPORT_PASSWORD_LINE="$(line_of_exact "$SCRIPT" '  -P "$SIGNING_DEVELOPER_ID_P12_PASSWORD" \')"
CLEAR_PRIVATE_PASSWORD_LINE="$(line_of_exact "$SCRIPT" 'unset SIGNING_DEVELOPER_ID_P12_PASSWORD')"
CLEANUP_CLEAR_LINE="$(line_of_exact "$SCRIPT" '  unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64 SIGNING_DEVELOPER_ID_P12_BASE64 SIGNING_DEVELOPER_ID_P12_PASSWORD SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64')"
CLEANUP_SECURITY_LINE="$(line_of_exact "$SCRIPT" '    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1')"

for capture_line in "$CAPTURE_P12_LINE" "$CAPTURE_PASSWORD_LINE" "$CAPTURE_API_KEY_LINE"; do
  (( capture_line < PRIVATE_EXPORT_CLEAR_LINE ))     || fail "signing secrets must be captured before private copies are de-exported"
done
(( PRIVATE_EXPORT_CLEAR_LINE < CLEAR_EXPORTED_LINE ))   || fail "private signing copies must be de-exported before original exported names are cleared"
(( CLEAR_EXPORTED_LINE < ROOT_LINE ))   || fail "exported signing secrets must be cleared before the first git subprocess"

(( CLEAR_EXPORTED_LINE < SCOPED_P12_LINE ))   || fail "credential validator exposure must be command-scoped after global secret clearing"
(( SCOPED_P12_LINE + 1 == SCOPED_PASSWORD_LINE ))   || fail "credential validator scoped password mapping must immediately follow PKCS#12 mapping"
(( SCOPED_PASSWORD_LINE + 1 == SCOPED_API_KEY_LINE ))   || fail "credential validator scoped API-key mapping must immediately follow password mapping"
(( SCOPED_API_KEY_LINE + 1 == VERIFY_INPUT_LINE ))   || fail "credential validator command must immediately follow scoped secret mappings"

(( VERIFY_INPUT_LINE < DECODE_P12_LINE ))   || fail "credential input validation must happen before PKCS#12 decode"
(( DECODE_P12_LINE < CLEAR_PRIVATE_ENCODED_LINE ))   || fail "private Developer ID base64 copy must be cleared after decode"
(( DECODE_API_KEY_LINE < CLEAR_PRIVATE_ENCODED_LINE ))   || fail "private App Store Connect base64 copy must be cleared after decode"
(( VERIFY_DECODED_PASSWORD_LINE < IMPORT_PASSWORD_LINE ))   || fail "private PKCS#12 password must be available through decoded validation and import"
(( IMPORT_PASSWORD_LINE < CLEAR_PRIVATE_PASSWORD_LINE ))   || fail "private PKCS#12 password must be cleared after keychain import"
(( CLEANUP_CLEAR_LINE < CLEANUP_SECURITY_LINE ))   || fail "failure cleanup must clear exported and private signing secret names before subprocesses"

echo 'Release secret export boundary verified'
