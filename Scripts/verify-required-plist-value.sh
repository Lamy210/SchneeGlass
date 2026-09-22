#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

PLIST_PATH="${1:-}"
KEY="${2:-}"
EXPECTED="${3:-}"
CONTEXT="${4:-Required plist validation}"
PLIST_BUDDY_BIN="${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"

fail() {
  echo "$CONTEXT failed: $*" >&2
  exit 1
}

[[ -n "$PLIST_PATH" ]] || fail 'plist path is required'
[[ -n "$KEY" ]] || fail 'plist key is required'
[[ -f "$PLIST_PATH" ]] || fail "plist file is missing: $PLIST_PATH"

# Mechanically extracted current semantics for RED/TDD.
test "$("$PLIST_BUDDY_BIN" -c "Print :$KEY" "$PLIST_PATH")" = "$EXPECTED" \
  || fail "unexpected value for $KEY"
