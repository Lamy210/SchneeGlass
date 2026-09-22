#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-production-path-coverage-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

REAL_GREP="$(command -v grep)"
OUTPUT="$FIXTURE/output.log"
SCOPE_OUTPUT="$FIXTURE/scope-output.log"
SCOPE_WORKFLOW="$FIXTURE/scope-workflow.yml"

REQUIRED_PATHS=(
  'Scripts/verify-release-metadata.sh'
  'Scripts/test-release-bundle-metadata-key-probe.sh'
  'Scripts/initialize-release-evidence-schema.sh'
  'Scripts/test-release-evidence-schema-probe.sh'
  'Scripts/verify-optional-release-entitlements.sh'
  'Scripts/test-optional-release-entitlement-probes.sh'
  'Scripts/verify-required-plist-value.sh'
  'Scripts/test-required-plist-value-probes.sh'
  'Scripts/verify-production-release-path-coverage.sh'
  'Scripts/test-production-release-path-coverage-enumeration.sh'
)

# Control: the real workflow remains fully covered.
bash Scripts/verify-production-release-path-coverage.sh \
  .github/workflows/production-release.yml \
  "${REQUIRED_PATHS[@]}" >/dev/null

# Scope regression: a same-indented value under pull_request.branches must not satisfy
# pull_request.paths coverage. The old helper scanned the whole pull_request block and
# therefore accepted this synthetic workflow.
cat > "$SCOPE_WORKFLOW" <<'EOF'
name: Synthetic path-scope fixture

on:
  pull_request:
    paths:
      - '.github/workflows/production-release.yml'
    branches:
      - 'Scripts/verify-release-metadata.sh'

permissions:
  contents: read
EOF

set +e
bash Scripts/verify-production-release-path-coverage.sh \
  "$SCOPE_WORKFLOW" \
  'Scripts/verify-release-metadata.sh' \
  >"$SCOPE_OUTPUT" 2>&1
SCOPE_STATUS=$?
set -e

if [[ "$SCOPE_STATUS" -eq 0 ]]; then
  cat "$SCOPE_OUTPUT"
  echo 'Production release path coverage unexpectedly accepted a required path outside pull_request.paths.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'Production release path coverage validation failed: pull_request.paths is missing required path: Scripts/verify-release-metadata.sh' \
  "$SCOPE_OUTPUT"

cat > "$FIXTURE/bin/sed" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
  pull_request:
    paths:
      - 'Scripts/verify-release-metadata.sh'
      - 'Scripts/test-release-bundle-metadata-key-probe.sh'
      - 'Scripts/initialize-release-evidence-schema.sh'
      - 'Scripts/test-release-evidence-schema-probe.sh'
      - 'Scripts/verify-optional-release-entitlements.sh'
      - 'Scripts/test-optional-release-entitlement-probes.sh'
      - 'Scripts/verify-required-plist-value.sh'
      - 'Scripts/test-required-plist-value-probes.sh'
      - 'Scripts/verify-production-release-path-coverage.sh'
      - 'Scripts/test-production-release-path-coverage-enumeration.sh'
permissions:
EOF
echo 'fixture: pull_request.paths enumeration failed after partial output' >&2
exit 42
SHIM
chmod +x "$FIXTURE/bin/sed"

set +e
PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/verify-production-release-path-coverage.sh \
  .github/workflows/production-release.yml \
  "${REQUIRED_PATHS[@]}" \
  >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Production release path coverage unexpectedly accepted partial enumeration output.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'Production release path coverage validation failed: unable to enumerate pull_request.paths (sed status 42)' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Production release path-coverage enumeration failure fixture passed'
