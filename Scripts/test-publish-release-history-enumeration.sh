#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

bash Scripts/test-publish-release-history-enumeration-base.sh
bash Scripts/test-publish-release-provenance.sh

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-build-history-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin" "$FIXTURE/history"

cat > "$FIXTURE/current.txt" <<'EOF'
schema_version=1
bundle_build=5
EOF

cat > "$FIXTURE/bin/find" <<'SHIM'
#!/usr/bin/env bash
exit 42
SHIM
chmod +x "$FIXTURE/bin/find"

OUTPUT="$FIXTURE/output.log"
set +e
PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/verify-release-build-history.sh \
    "$FIXTURE/current.txt" \
    "$FIXTURE/history" \
    >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'Release build history validator unexpectedly accepted evidence enumeration failure.' >&2
  exit 1
fi

grep -Fq \
  'Release build history validation failed: failed to enumerate historical release evidence' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Release build history enumeration failure fixture passed'
