#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENTITLEMENTS_PATH="${1:-}"
CONTEXT="${2:-Release entitlement validation}"
PLIST_BUDDY_BIN="${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"

fail() {
  echo "$CONTEXT failed: $*" >&2
  exit 1
}

[[ -n "$ENTITLEMENTS_PATH" ]] || fail 'entitlements path is required'
[[ -f "$ENTITLEMENTS_PATH" ]] || fail "entitlements file is missing: $ENTITLEMENTS_PATH"
plutil -lint "$ENTITLEMENTS_PATH" >/dev/null

# Mechanically extracted from the two production release paths for TDD.
# The RED fixture demonstrates that probe-process failures are currently
# indistinguishable from confirmed key absence.
if "$PLIST_BUDDY_BIN"   -c 'Print :com.apple.security.network.client'   "$ENTITLEMENTS_PATH" >/dev/null 2>&1; then
  fail 'unexpected network client entitlement'
fi

if GET_TASK_ALLOW="$("$PLIST_BUDDY_BIN"   -c 'Print :com.apple.security.get-task-allow'   "$ENTITLEMENTS_PATH" 2>/dev/null)"; then
  [[ "$GET_TASK_ALLOW" != 'true' ]]     || fail 'get-task-allow must not be enabled for notarized distribution'
fi
