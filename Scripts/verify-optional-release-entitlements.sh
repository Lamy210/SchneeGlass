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

probe_entitlement() {
  local key="$1"
  local output
  local status

  set +e
  output="$("$PLIST_BUDDY_BIN" -c "Print :$key" "$ENTITLEMENTS_PATH" 2>&1)"
  status=$?
  set -e

  case "$status" in
    0)
      printf '%s' "$output"
      return 0
      ;;
    1)
      if [[ "$output" == *"$key"* && "$output" == *'Does Not Exist'* ]]; then
        return 1
      fi
      fail "unable to inspect entitlement $key (PlistBuddy status $status)"
      ;;
    *)
      fail "unable to inspect entitlement $key (PlistBuddy status $status)"
      ;;
  esac
}

set +e
NETWORK_CLIENT="$(probe_entitlement 'com.apple.security.network.client')"
NETWORK_STATUS=$?
set -e

case "$NETWORK_STATUS" in
  0)
    fail 'unexpected network client entitlement'
    ;;
  1)
    ;;
  *)
    exit "$NETWORK_STATUS"
    ;;
esac

set +e
GET_TASK_ALLOW="$(probe_entitlement 'com.apple.security.get-task-allow')"
GET_TASK_STATUS=$?
set -e

case "$GET_TASK_STATUS" in
  0)
    case "$GET_TASK_ALLOW" in
      true)
        fail 'get-task-allow must not be enabled for notarized distribution'
        ;;
      false)
        ;;
      *)
        fail "unexpected value for com.apple.security.get-task-allow: $GET_TASK_ALLOW"
        ;;
    esac
    ;;
  1)
    ;;
  *)
    exit "$GET_TASK_STATUS"
    ;;
esac
