#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-evidence-schema-probe-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

REAL_GREP="$(command -v grep)"

# Control: schema-less evidence receives exactly one leading schema key.
CONTROL="$FIXTURE/control.txt"
cat > "$CONTROL" <<'EOF'
version=0.1.0
notarization_status=Accepted
EOF
bash Scripts/initialize-release-evidence-schema.sh "$CONTROL"
[[ "$(head -n 1 "$CONTROL")" == 'schema_version=1' ]]
[[ "$("$REAL_GREP" -c '^schema_version=' "$CONTROL")" == '1' ]]

# Duplicate control: an existing schema key must be rejected and left unchanged.
DUPLICATE="$FIXTURE/duplicate.txt"
cat > "$DUPLICATE" <<'EOF'
schema_version=1
version=0.1.0
EOF
cp "$DUPLICATE" "$FIXTURE/duplicate-before.txt"

set +e
bash Scripts/initialize-release-evidence-schema.sh "$DUPLICATE"   >"$FIXTURE/duplicate.log" 2>&1
DUPLICATE_STATUS=$?
set -e

if [[ "$DUPLICATE_STATUS" -eq 0 ]]; then
  cat "$FIXTURE/duplicate.log"
  echo 'Schema initializer unexpectedly accepted a pre-existing schema key.' >&2
  exit 1
fi
"$REAL_GREP" -Fq   'Release evidence schema initialization failed: release evidence already contains schema_version'   "$FIXTURE/duplicate.log"
cmp -s "$FIXTURE/duplicate-before.txt" "$DUPLICATE" || {
  diff -u "$FIXTURE/duplicate-before.txt" "$DUPLICATE" >&2 || true
  echo 'Evidence changed after duplicate schema rejection.' >&2
  exit 1
}

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == '-q' && "${2:-}" == '^schema_version=' ]]; then
  echo 'fixture: schema probe unavailable' >&2
  exit 42
fi

echo "fixture: unexpected grep invocation: $*" >&2
exit 91
SHIM
chmod +x "$FIXTURE/bin/grep"

FAILURE="$FIXTURE/failure.txt"
cat > "$FAILURE" <<'EOF'
version=0.1.0
notarization_status=Accepted
EOF
cp "$FAILURE" "$FIXTURE/failure-before.txt"

set +e
PATH="$FIXTURE/bin:$PATH"   bash Scripts/initialize-release-evidence-schema.sh "$FAILURE"   >"$FIXTURE/failure.log" 2>&1
FAILURE_STATUS=$?
set -e

if [[ "$FAILURE_STATUS" -eq 0 ]]; then
  cat "$FIXTURE/failure.log"
  echo 'Schema initializer unexpectedly treated probe failure as schema absence.' >&2
  exit 1
fi
"$REAL_GREP" -Fq   'Release evidence schema initialization failed: unable to probe schema_version (grep status 42)'   "$FIXTURE/failure.log"
cmp -s "$FIXTURE/failure-before.txt" "$FAILURE" || {
  diff -u "$FIXTURE/failure-before.txt" "$FAILURE" >&2 || true
  echo 'Evidence changed after ambiguous schema probe.' >&2
  exit 1
}

rm -rf "$FIXTURE"
echo 'Release evidence schema-probe fixtures passed'
