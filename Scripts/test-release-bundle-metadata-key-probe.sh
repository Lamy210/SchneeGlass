#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-bundle-metadata-key-probe-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/SchneeGlass.app/Contents" "$FIXTURE/bin"

ARCHIVE="$FIXTURE/SchneeGlass-0.0.0.zip"
BASE_EVIDENCE="$FIXTURE/base-evidence.txt"
CONTROL_EVIDENCE="$FIXTURE/control-evidence.txt"
DUPLICATE_EVIDENCE="$FIXTURE/duplicate-evidence.txt"
FAILURE_EVIDENCE="$FIXTURE/failure-evidence.txt"
FAILURE_BEFORE="$FIXTURE/failure-before.txt"
OUTPUT="$FIXTURE/output.log"
REAL_GREP="$(command -v grep)"

cat > "$FIXTURE/SchneeGlass.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>io.github.lamy210.schneeglass</string>
  <key>CFBundleShortVersionString</key>
  <string>0.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
</dict>
</plist>
PLIST

ditto -c -k --sequesterRsrc --keepParent   "$FIXTURE/SchneeGlass.app"   "$ARCHIVE"

cat > "$BASE_EVIDENCE" <<'EOF'
schema_version=1
version=0.0.0
EOF

# Control: confirmed absence permits metadata recording.
cp "$BASE_EVIDENCE" "$CONTROL_EVIDENCE"
bash Scripts/record-release-bundle-metadata.sh   0.0.0   "$ARCHIVE"   "$CONTROL_EVIDENCE"
"$REAL_GREP" -Fxq 'bundle_identifier=io.github.lamy210.schneeglass' "$CONTROL_EVIDENCE"
"$REAL_GREP" -Fxq 'bundle_version=0.0.0' "$CONTROL_EVIDENCE"
"$REAL_GREP" -Fxq 'bundle_build=1' "$CONTROL_EVIDENCE"

# Control: a confirmed duplicate key remains rejected.
cp "$BASE_EVIDENCE" "$DUPLICATE_EVIDENCE"
printf '%s\n' 'bundle_identifier=already-present' >> "$DUPLICATE_EVIDENCE"
set +e
bash Scripts/record-release-bundle-metadata.sh   0.0.0   "$ARCHIVE"   "$DUPLICATE_EVIDENCE"   >"$FIXTURE/duplicate.log" 2>&1
DUPLICATE_STATUS=$?
set -e
[[ "$DUPLICATE_STATUS" -ne 0 ]]
"$REAL_GREP" -Fq   'Release bundle metadata validation failed: release evidence already contains bundle_identifier'   "$FIXTURE/duplicate.log"

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == '-q' ]]; then
  echo 'fixture: release evidence key probe unavailable' >&2
  exit 42
fi

echo "fixture: unexpected grep invocation: $*" >&2
exit 91
SHIM
chmod +x "$FIXTURE/bin/grep"

cp "$BASE_EVIDENCE" "$FAILURE_EVIDENCE"
cp "$FAILURE_EVIDENCE" "$FAILURE_BEFORE"

set +e
PATH="$FIXTURE/bin:$PATH"   bash Scripts/record-release-bundle-metadata.sh   0.0.0   "$ARCHIVE"   "$FAILURE_EVIDENCE"   >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Bundle metadata recorder unexpectedly accepted an unavailable evidence-key probe.' >&2
  exit 1
fi

"$REAL_GREP" -Fq   'Release bundle metadata validation failed: unable to probe release evidence key: bundle_identifier (grep status 42)'   "$OUTPUT"

cmp -s "$FAILURE_BEFORE" "$FAILURE_EVIDENCE" || {
  diff -u "$FAILURE_BEFORE" "$FAILURE_EVIDENCE" >&2 || true
  echo 'Release evidence changed after an ambiguous metadata-key probe.' >&2
  exit 1
}

rm -rf "$FIXTURE"
echo 'Release bundle metadata key-probe failure fixture passed'
