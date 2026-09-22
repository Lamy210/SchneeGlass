#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-required-plist-probe-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

PLIST="$FIXTURE/fixture.plist"
REAL_PLIST_BUDDY="/usr/libexec/PlistBuddy"
REAL_GREP="$(command -v grep)"

cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>RequiredFlag</key>
  <true/>
  <key>BundleID</key>
  <string>io.github.lamy210.schneeglass</string>
</dict>
</plist>
PLIST

plutil -lint "$PLIST" >/dev/null

bash Scripts/verify-required-plist-value.sh \
  "$PLIST" \
  'RequiredFlag' \
  'true' \
  'Required plist fixture'

bash Scripts/verify-required-plist-value.sh \
  "$PLIST" \
  'BundleID' \
  'io.github.lamy210.schneeglass' \
  'Required plist fixture'

set +e
bash Scripts/verify-required-plist-value.sh \
  "$PLIST" \
  'BundleID' \
  'wrong.example' \
  'Required plist fixture' \
  >"$FIXTURE/wrong-value.log" 2>&1
WRONG_STATUS=$?
set -e
[[ "$WRONG_STATUS" -ne 0 ]]
"$REAL_GREP" -Fq 'Required plist fixture failed: unexpected value for BundleID' "$FIXTURE/wrong-value.log"

cat > "$FIXTURE/bin/PlistBuddy" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}:${2:-}" in
  '-c:Print :RequiredFlag')
    printf '%s\n' 'true'
    echo 'fixture: required plist probe unavailable after partial expected output' >&2
    exit 42
    ;;
  '-c:Print :BundleID')
    printf '%s\n' 'io.github.lamy210.schneeglass'
    echo 'fixture: required plist probe unavailable after partial expected output' >&2
    exit 42
    ;;
esac

echo "fixture: unexpected PlistBuddy invocation: $*" >&2
exit 91
SHIM
chmod +x "$FIXTURE/bin/PlistBuddy"

run_partial_failure() {
  local key="$1"
  local expected="$2"
  local output="$3"

  set +e
  PLIST_BUDDY_BIN="$FIXTURE/bin/PlistBuddy" \
    bash Scripts/verify-required-plist-value.sh \
      "$PLIST" \
      "$key" \
      "$expected" \
      'Required plist fixture' \
      >"$output" 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    cat "$output"
    echo "Required plist verifier unexpectedly accepted partial expected output after probe failure: $key" >&2
    exit 1
  fi

  "$REAL_GREP" -Fq \
    "Required plist fixture failed: unable to read required plist key $key (PlistBuddy status 42)" \
    "$output"
}

run_partial_failure 'RequiredFlag' 'true' "$FIXTURE/partial-boolean.log"
run_partial_failure 'BundleID' 'io.github.lamy210.schneeglass' "$FIXTURE/partial-string.log"

rm -rf "$FIXTURE"
echo 'Required plist probe failure fixtures passed'
