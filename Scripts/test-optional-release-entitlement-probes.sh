#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-optional-entitlement-probe-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

REAL_PLIST_BUDDY='/usr/libexec/PlistBuddy'
REAL_GREP="$(command -v grep)"

write_plist() {
  local path="$1"
  local network_value="${2:-absent}"
  local get_task_value="${3:-absent}"

  cat > "$path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.app-sandbox</key>
  <true/>
  <key>com.apple.security.files.user-selected.read-write</key>
  <true/>
</dict>
</plist>
PLIST

  if [[ "$network_value" != 'absent' ]]; then
    "$REAL_PLIST_BUDDY" -c "Add :com.apple.security.network.client bool $network_value" "$path"
  fi
  if [[ "$get_task_value" != 'absent' ]]; then
    "$REAL_PLIST_BUDDY" -c "Add :com.apple.security.get-task-allow bool $get_task_value" "$path"
  fi
}

ABSENT="$FIXTURE/absent.plist"
write_plist "$ABSENT"
bash Scripts/verify-optional-release-entitlements.sh   "$ABSENT"   'Optional entitlement fixture'

NETWORK="$FIXTURE/network.plist"
write_plist "$NETWORK" true absent
set +e
bash Scripts/verify-optional-release-entitlements.sh   "$NETWORK"   'Optional entitlement fixture'   >"$FIXTURE/network.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
"$REAL_GREP" -Fq   'Optional entitlement fixture failed: unexpected network client entitlement'   "$FIXTURE/network.log"

GET_TASK_TRUE="$FIXTURE/get-task-true.plist"
write_plist "$GET_TASK_TRUE" absent true
set +e
bash Scripts/verify-optional-release-entitlements.sh   "$GET_TASK_TRUE"   'Optional entitlement fixture'   >"$FIXTURE/get-task-true.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
"$REAL_GREP" -Fq   'Optional entitlement fixture failed: get-task-allow must not be enabled for notarized distribution'   "$FIXTURE/get-task-true.log"

GET_TASK_FALSE="$FIXTURE/get-task-false.plist"
write_plist "$GET_TASK_FALSE" absent false
bash Scripts/verify-optional-release-entitlements.sh   "$GET_TASK_FALSE"   'Optional entitlement fixture'

cat > "$FIXTURE/bin/PlistBuddy" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

MODE="${OPTIONAL_ENTITLEMENT_PROBE_MODE:?}"
REAL="${REAL_PLIST_BUDDY:?}"
COMMAND=''

if [[ "${1:-}" == '-c' ]]; then
  COMMAND="${2:-}"
fi

case "$MODE:$COMMAND" in
  network-failure:'Print :com.apple.security.network.client')
    echo 'fixture: network-client entitlement probe unavailable' >&2
    exit 42
    ;;
  get-task-failure:'Print :com.apple.security.get-task-allow')
    echo 'fixture: get-task-allow entitlement probe unavailable' >&2
    exit 42
    ;;
esac

exec "$REAL" "$@"
SHIM
chmod +x "$FIXTURE/bin/PlistBuddy"

run_probe_failure() {
  local mode="$1"
  local expected_key="$2"
  local output="$3"

  set +e
  OPTIONAL_ENTITLEMENT_PROBE_MODE="$mode"     REAL_PLIST_BUDDY="$REAL_PLIST_BUDDY"     PLIST_BUDDY_BIN="$FIXTURE/bin/PlistBuddy"     bash Scripts/verify-optional-release-entitlements.sh       "$ABSENT"       'Optional entitlement fixture'       >"$output" 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    cat "$output"
    echo "Optional entitlement validator unexpectedly accepted probe failure: $mode" >&2
    exit 1
  fi

  "$REAL_GREP" -Fq     "Optional entitlement fixture failed: unable to inspect entitlement $expected_key (PlistBuddy status 42)"     "$output"
}

run_probe_failure   'network-failure'   'com.apple.security.network.client'   "$FIXTURE/network-failure.log"

run_probe_failure   'get-task-failure'   'com.apple.security.get-task-allow'   "$FIXTURE/get-task-failure.log"

rm -rf "$FIXTURE"
echo 'Optional release entitlement probe fixtures passed'
