#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

WORKFLOW="${1:-.github/workflows/publish-release.yml}"
FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-publish-release-path-coverage"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"

COVERAGE_STEP="$FIXTURE/publication-path-coverage-step.txt"

fail() {
  echo "Publish release path coverage fixture failed: $*" >&2
  exit 1
}

REQUIRED_PATHS=(
  '.github/workflows/publish-release.yml'
  '.github/rulesets/main-release-governance.json'
  'Scripts/publish-notarized-release.sh'
  'Scripts/materialize-public-release-build-history.sh'
  'Scripts/verify-legacy-release-build-info.sh'
  'Scripts/test-public-release-build-history-materialization.sh'
  'Scripts/test-legacy-release-build-info.sh'
  'docs/release-history/legacy-public-releases.tsv'
  'Scripts/verify-current-release-governance.sh'
  'Scripts/test-publish-release-history-enumeration.sh'
  'Scripts/test-publish-release-history-enumeration-base.sh'
  'Scripts/test-publish-release-provenance.sh'
  'Scripts/verify-production-candidate-run.sh'
  'Scripts/verify-release-build-history.sh'
  'Scripts/test-release-build-history-key-enumeration.sh'
  'Scripts/verify-release-evidence.sh'
  'Scripts/test-release-evidence-enumeration.sh'
  'Scripts/verify-release-checksum-manifest.sh'
  'Scripts/test-release-checksum-manifest.sh'
  'Scripts/verify-production-release-path-coverage.sh'
  'Scripts/test-production-release-path-coverage-enumeration.sh'
  'Scripts/verify-release-branch-protection.sh'
  'Scripts/verify-release-required-branch-rules.sh'
  'Scripts/verify-release-required-checks.sh'
  'Scripts/test-publish-release-path-coverage.sh'
)

bash Scripts/verify-production-release-path-coverage.sh \
  "$WORKFLOW" \
  "${REQUIRED_PATHS[@]}" >/dev/null \
  || fail "pull_request.paths does not contain the complete publish release trigger set"

awk '
  $0 == "      - name: Publication fixture path coverage" {
    in_step = 1
    next
  }
  in_step && $0 ~ /^      - name:/ {
    exit
  }
  in_step {
    print
  }
' "$WORKFLOW" > "$COVERAGE_STEP"

[[ -s "$COVERAGE_STEP" ]] \
  || fail "Publication fixture path coverage step is missing or empty"

for required_path in "${REQUIRED_PATHS[@]}"; do
  if ! grep -Fq "'$required_path'" "$COVERAGE_STEP"; then
    fail "Publication fixture path coverage step is missing required path: $required_path"
  fi
done

rm -rf "$FIXTURE"
echo 'Publish release path coverage fixture passed'
