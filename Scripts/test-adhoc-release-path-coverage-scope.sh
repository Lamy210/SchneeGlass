#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-adhoc-path-coverage-scope-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"

SCOPE_WORKFLOW="$FIXTURE/scope-workflow.yml"
OUTPUT="$FIXTURE/output.log"

# Control: the real workflow remains covered.
bash Scripts/test-adhoc-release-path-coverage.sh \
  .github/workflows/adhoc-release-candidate.yml >/dev/null

# Every other required trigger is present in pull_request.paths. App/Info.plist is deliberately
# placed at the same indentation under branches so only a scope bug could make validation pass.
cat > "$SCOPE_WORKFLOW" <<'EOF'
name: Synthetic ad-hoc path-scope fixture

on:
  pull_request:
    paths:
      - '.github/workflows/adhoc-release-candidate.yml'
      - 'Scripts/build-adhoc-release-candidate.sh'
      - 'Scripts/verify-adhoc-signature-details.sh'
      - 'Scripts/test-adhoc-signature-details.sh'
      - 'Scripts/verify-adhoc-candidate-source.sh'
      - 'Scripts/test-adhoc-candidate-source.sh'
      - 'Scripts/test-adhoc-release-single-instance-bundle-policy.sh'
      - 'Scripts/test-adhoc-release-path-coverage.sh'
      - 'Scripts/test-adhoc-release-path-coverage-scope.sh'
      - 'Scripts/resolve-release-version.sh'
      - 'Scripts/verify-release-metadata.sh'
      - 'Scripts/verify-required-plist-value.sh'
      - 'Scripts/verify-optional-release-entitlements.sh'
      - 'Scripts/verify-xcode-version.sh'
      - 'App/SchneeGlass.entitlements'
      - 'SchneeGlass.xcodeproj/project.pbxproj'
      - 'RELEASE.md'
    branches:
      - 'App/Info.plist'

permissions:
  contents: read
EOF

set +e
bash Scripts/test-adhoc-release-path-coverage.sh \
  "$SCOPE_WORKFLOW" \
  >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Ad-hoc release path coverage unexpectedly accepted App/Info.plist outside pull_request.paths.' >&2
  exit 1
fi

grep -Fq \
  'Ad-hoc release path coverage validation failed: expected exactly one pull_request path for App/Info.plist; found 0' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Ad-hoc release path-coverage scope fixture passed'
