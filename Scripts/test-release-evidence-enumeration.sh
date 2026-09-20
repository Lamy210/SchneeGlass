#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-evidence-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

EVIDENCE="$FIXTURE/RELEASE_EVIDENCE.txt"
OUTPUT="$FIXTURE/output.log"
REAL_GREP="$(command -v grep)"
EXPECTED_COMMIT='0123456789abcdef0123456789abcdef01234567'

cat > "$EVIDENCE" <<'EOF'
schema_version=1
version=0.1.0
notarization_id=12345678-1234-1234-1234-1234567890ab
notarization_status=Accepted
codesign=verified
stapler=validated
gatekeeper=accepted
bundle_identifier=io.github.lamy210.schneeglass
bundle_version=0.1.0
bundle_build=1
commit_sha=0123456789abcdef0123456789abcdef01234567
EOF

# Control: valid evidence remains accepted with the real grep implementation.
bash Scripts/verify-release-evidence.sh "$EVIDENCE" 0.1.0 "$EXPECTED_COMMIT" >/dev/null

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == '-c' ]]; then
  printf '1\n'
  echo 'fixture: evidence key enumeration unavailable after partial count' >&2
  exit 42
fi

echo "fixture: unexpected grep invocation: $*" >&2
exit 91
SHIM
chmod +x "$FIXTURE/bin/grep"

set +e
PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/verify-release-evidence.sh "$EVIDENCE" 0.1.0 "$EXPECTED_COMMIT" \
  >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Release evidence validator unexpectedly accepted partial key-count output after grep failure.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'Release evidence validation failed: unable to enumerate evidence key: schema_version (grep status 42)' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Release evidence key-enumeration failure fixture passed'
