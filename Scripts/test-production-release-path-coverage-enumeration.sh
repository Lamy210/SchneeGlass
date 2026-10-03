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
MISSING_PATH_OUTPUT="$FIXTURE/missing-path-output.log"
MISSING_PATH_WORKFLOW="$FIXTURE/missing-path-workflow.yml"

REQUIRED_PATHS=(
  '.github/workflows/production-release.yml'
  'Scripts/build-notarized-release.sh'
  'Scripts/verify-xcode-version.sh'
  'Scripts/record-release-bundle-metadata.sh'
  'Scripts/test-release-bundle-metadata-key-probe.sh'
  'Scripts/initialize-release-evidence-schema.sh'
  'Scripts/test-release-evidence-schema-probe.sh'
  'Scripts/verify-release-metadata.sh'
  'Scripts/resolve-release-version.sh'
  'Scripts/verify-release-credential-inputs.sh'
  'Scripts/verify-release-decoded-credentials.sh'
  'Scripts/encode-release-fixture-base64.sh'
  'Scripts/test-release-fixture-base64-encoding.sh'
  'Scripts/verify-release-evidence.sh'
  'Scripts/verify-release-checksum-manifest.sh'
  'Scripts/test-release-checksum-manifest.sh'
  'Scripts/verify-production-release-preflight.sh'
  'Scripts/verify-optional-release-entitlements.sh'
  'Scripts/test-optional-release-entitlement-probes.sh'
  'Scripts/verify-required-plist-value.sh'
  'Scripts/test-required-plist-value-probes.sh'
  'Scripts/verify-production-release-path-coverage.sh'
  'Scripts/verify-production-release-secret-scope.sh'
  'Scripts/test-production-release-secret-scope.sh'
  'Scripts/verify-release-secret-environment-lifecycle.sh'
  'Scripts/test-release-secret-environment-lifecycle.sh'
  'Scripts/verify-release-secret-export-boundary.sh'
  'Scripts/test-release-secret-export-boundary.sh'
  'Scripts/test-production-release-path-coverage-enumeration.sh'
  'App/Info.plist'
  'App/SchneeGlass.entitlements'
  'SchneeGlass.xcodeproj/project.pbxproj'
  'docs/RELEASE_CREDENTIALS.md'
)

# Control: every file that can change production preflight policy must trigger this workflow.
bash Scripts/verify-production-release-path-coverage.sh \
  .github/workflows/production-release.yml \
  "${REQUIRED_PATHS[@]}" >/dev/null

# Regression: these release-critical inputs already trigger the workflow today, but the
# canonical REQUIRED_PATHS set did not protect them. Removing any one of them must make this
# fixture fail, otherwise a future workflow edit could silently re-open the trigger gap.
UNCOVERED_CRITICAL_PATHS=(
  '.github/workflows/production-release.yml'
  'Scripts/build-notarized-release.sh'
  'Scripts/verify-xcode-version.sh'
  'Scripts/record-release-bundle-metadata.sh'
  'Scripts/resolve-release-version.sh'
  'Scripts/verify-release-credential-inputs.sh'
  'Scripts/verify-release-decoded-credentials.sh'
  'Scripts/encode-release-fixture-base64.sh'
  'Scripts/test-release-fixture-base64-encoding.sh'
  'Scripts/verify-release-evidence.sh'
  'Scripts/verify-release-checksum-manifest.sh'
  'Scripts/test-release-checksum-manifest.sh'
  'Scripts/verify-production-release-preflight.sh'
  'Scripts/verify-production-release-secret-scope.sh'
  'Scripts/test-production-release-secret-scope.sh'
  'Scripts/verify-release-secret-environment-lifecycle.sh'
  'Scripts/test-release-secret-environment-lifecycle.sh'
  'Scripts/verify-release-secret-export-boundary.sh'
  'Scripts/test-release-secret-export-boundary.sh'
  'docs/RELEASE_CREDENTIALS.md'
)

for missing_path in "${UNCOVERED_CRITICAL_PATHS[@]}"; do
  "$REAL_GREP" -Fv \
    "      - '$missing_path'" \
    .github/workflows/production-release.yml \
    > "$MISSING_PATH_WORKFLOW"

  set +e
  bash Scripts/verify-production-release-path-coverage.sh \
    "$MISSING_PATH_WORKFLOW" \
    "${REQUIRED_PATHS[@]}" \
    >"$MISSING_PATH_OUTPUT" 2>&1
  MISSING_PATH_STATUS=$?
  set -e

  if [[ "$MISSING_PATH_STATUS" -eq 0 ]]; then
    cat "$MISSING_PATH_OUTPUT"
    echo "Production release path-coverage fixture unexpectedly accepted a workflow missing: $missing_path" >&2
    exit 1
  fi

  "$REAL_GREP" -Fq \
    "Production release path coverage validation failed: pull_request.paths is missing required path: $missing_path" \
    "$MISSING_PATH_OUTPUT"
done

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
      - '.github/workflows/production-release.yml'
      - 'Scripts/build-notarized-release.sh'
      - 'Scripts/verify-xcode-version.sh'
      - 'Scripts/record-release-bundle-metadata.sh'
      - 'Scripts/test-release-bundle-metadata-key-probe.sh'
      - 'Scripts/initialize-release-evidence-schema.sh'
      - 'Scripts/test-release-evidence-schema-probe.sh'
      - 'Scripts/verify-release-metadata.sh'
      - 'Scripts/resolve-release-version.sh'
      - 'Scripts/verify-release-credential-inputs.sh'
      - 'Scripts/verify-release-decoded-credentials.sh'
      - 'Scripts/encode-release-fixture-base64.sh'
      - 'Scripts/test-release-fixture-base64-encoding.sh'
      - 'Scripts/verify-release-evidence.sh'
      - 'Scripts/verify-release-checksum-manifest.sh'
      - 'Scripts/test-release-checksum-manifest.sh'
      - 'Scripts/verify-production-release-preflight.sh'
      - 'Scripts/verify-optional-release-entitlements.sh'
      - 'Scripts/test-optional-release-entitlement-probes.sh'
      - 'Scripts/verify-required-plist-value.sh'
      - 'Scripts/test-required-plist-value-probes.sh'
      - 'Scripts/verify-production-release-path-coverage.sh'
      - 'Scripts/verify-production-release-secret-scope.sh'
      - 'Scripts/test-production-release-secret-scope.sh'
      - 'Scripts/verify-release-secret-environment-lifecycle.sh'
      - 'Scripts/test-release-secret-environment-lifecycle.sh'
      - 'Scripts/verify-release-secret-export-boundary.sh'
      - 'Scripts/test-release-secret-export-boundary.sh'
      - 'Scripts/test-production-release-path-coverage-enumeration.sh'
      - 'App/Info.plist'
      - 'App/SchneeGlass.entitlements'
      - 'SchneeGlass.xcodeproj/project.pbxproj'
      - 'docs/RELEASE_CREDENTIALS.md'
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
