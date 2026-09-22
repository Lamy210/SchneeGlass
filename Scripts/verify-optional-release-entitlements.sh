#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

ENTITLEMENTS_PATH="${1:-}"
CONTEXT="${2:-Release entitlement validation}"
PLIST_BUDDY_BIN="${PLIST_BUDDY_BIN:-/usr/libexec/PlistBuddy}"
PROBE_VALUE=''

fail() {
  echo "$CONTEXT failed: $*" >&2
  exit 1
}

[[ -n "$ENTITLEMENTS_PATH" ]] || fail 'entitlements path is required'
[[ -f "$ENTITLEMENTS_PATH" ]] || fail "entitlements file is missing: $ENTITLEMENTS_PATH"
plutil -lint "$ENTITLEMENTS_PATH" >/dev/null

probe_entitlement() {
  local key="$1"
  local output
  local status

  if output="$("$PLIST_BUDDY_BIN" -c "Print :$key" "$ENTITLEMENTS_PATH" 2>&1)"; then
    PROBE_VALUE="$output"
    return 0
  else
    status=$?
  fi

  if [[ "$status" -eq 1 && "$output" == *'Does Not Exist'* ]]; then
    PROBE_VALUE=''
    return 1
  fi

  fail "unable to inspect entitlement $key (PlistBuddy status $status)"
}

if probe_entitlement 'com.apple.security.network.client'; then
  fail 'unexpected network client entitlement'
else
  NETWORK_STATUS=$?
  [[ "$NETWORK_STATUS" -eq 1 ]] || exit "$NETWORK_STATUS"
fi

if probe_entitlement 'com.apple.security.get-task-allow'; then
  case "$PROBE_VALUE" in
    true)
      fail 'get-task-allow must not be enabled for notarized distribution'
      ;;
    false)
      ;;
    *)
      fail "unexpected value for com.apple.security.get-task-allow: $PROBE_VALUE"
      ;;
  esac
else
  GET_TASK_STATUS=$?
  [[ "$GET_TASK_STATUS" -eq 1 ]] || exit "$GET_TASK_STATUS"
fi
