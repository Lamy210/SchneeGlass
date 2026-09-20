#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-build-history-key-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin" "$FIXTURE/history/one"

CURRENT="$FIXTURE/current.txt"
HISTORICAL="$FIXTURE/history/one/RELEASE_EVIDENCE.txt"
OUTPUT="$FIXTURE/output.log"
REAL_GREP="$(command -v grep)"

cat > "$CURRENT" <<'EOF'
schema_version=1
bundle_build=5
EOF

cat > "$HISTORICAL" <<'EOF'
schema_version=1
bundle_build=4
EOF

# Control: valid monotonic history remains accepted with the real grep.
bash Scripts/verify-release-build-history.sh "$CURRENT" "$FIXTURE/history" >/dev/null

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == '-c' ]]; then
  printf '1\n'
  echo 'fixture: release build-history key enumeration unavailable after partial count' >&2
  exit 42
fi

echo "fixture: unexpected grep invocation: $*" >&2
exit 91
SHIM
chmod +x "$FIXTURE/bin/grep"

set +e
PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/verify-release-build-history.sh "$CURRENT" "$FIXTURE/history" \
  >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Release build-history validator unexpectedly accepted partial key-count output after grep failure.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'Release build history validation failed: unable to enumerate schema_version in release evidence' \
  "$OUTPUT"
"$REAL_GREP" -Fq '(grep status 42)' "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Release build-history key-enumeration failure fixture passed'
