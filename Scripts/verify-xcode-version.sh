#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Xcode version verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <expected-first-line>"
EXPECTED_FIRST_LINE="$1"
[[ -n "$EXPECTED_FIRST_LINE" ]] || fail "expected first line must not be empty"
command -v xcodebuild >/dev/null 2>&1 || fail "xcodebuild is required"

OUTPUT=''
STATUS=0

set +e
OUTPUT="$(xcodebuild -version 2>&1)"
STATUS=$?
set -e

if [[ -n "$OUTPUT" ]]; then
  printf '%s\n' "$OUTPUT"
fi

if [[ "$STATUS" -ne 0 ]]; then
  fail "xcodebuild -version exited with status $STATUS"
fi

FIRST_LINE="${OUTPUT%%$'\n'*}"
if [[ "$FIRST_LINE" != "$EXPECTED_FIRST_LINE" ]]; then
  fail "expected first line '$EXPECTED_FIRST_LINE'; found '$FIRST_LINE'"
fi

echo "Xcode version verified: $EXPECTED_FIRST_LINE"
