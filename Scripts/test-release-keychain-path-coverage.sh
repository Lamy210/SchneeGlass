#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

WORKFLOW='.github/workflows/release-keychain-enumeration-tests.yml'
FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-keychain-path-coverage-fixture"
MISSING_WORKFLOW="$FIXTURE/missing-path-workflow.yml"
MISSING_OUTPUT="$FIXTURE/missing-path-output.log"
REAL_GREP="$(command -v grep)"

rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"
cleanup() {
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

REQUIRED_PATHS=(
  '.github/workflows/release-keychain-enumeration-tests.yml'
  'Scripts/verify-xcode-version.sh'
  'Scripts/build-notarized-release.sh'
  'Scripts/encode-release-fixture-base64.sh'
  'Scripts/test-build-notarized-release-keychain-enumeration.sh'
  'Scripts/test-build-notarized-release-identity-enumeration.sh'
  'Scripts/resolve-release-version.sh'
  'SchneeGlass.xcodeproj/project.pbxproj'
  'Scripts/verify-production-release-path-coverage.sh'
  'Scripts/test-release-keychain-path-coverage.sh'
)

bash Scripts/verify-production-release-path-coverage.sh \
  "$WORKFLOW" \
  "${REQUIRED_PATHS[@]}" >/dev/null

for missing_path in "${REQUIRED_PATHS[@]}"; do
  "$REAL_GREP" -Fv \
    "      - '$missing_path'" \
    "$WORKFLOW" \
    > "$MISSING_WORKFLOW"

  set +e
  bash Scripts/verify-production-release-path-coverage.sh \
    "$MISSING_WORKFLOW" \
    "${REQUIRED_PATHS[@]}" \
    >"$MISSING_OUTPUT" 2>&1
  MISSING_STATUS=$?
  set -e

  if [[ "$MISSING_STATUS" -eq 0 ]]; then
    cat "$MISSING_OUTPUT"
    echo "Keychain path-coverage fixture unexpectedly accepted a workflow missing: $missing_path" >&2
    exit 1
  fi

  "$REAL_GREP" -Fq \
    "Production release path coverage validation failed: pull_request.paths is missing required path: $missing_path" \
    "$MISSING_OUTPUT"
done

echo 'Keychain release path coverage fixture passed'
