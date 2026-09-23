#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release fixture Base64 encoding failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <input-file>"
INPUT="$1"
[[ -f "$INPUT" ]] || fail "input file is missing: $INPUT"

BASE64_BIN="${SCHNEEGLASS_FIXTURE_BASE64_BIN:-/usr/bin/base64}"
[[ -x "$BASE64_BIN" ]] || fail "Base64 encoder is not executable: $BASE64_BIN"

ENCODED=''
STATUS=0
set +e
ENCODED="$("$BASE64_BIN" < "$INPUT" | tr -d '\n')"
STATUS=$?
set -e

[[ "$STATUS" -eq 0 ]] \
  || fail "Base64 encoder pipeline exited with status $STATUS"
[[ -n "$ENCODED" ]] \
  || fail "Base64 encoder returned empty output"

printf '%s\n' "$ENCODED"
