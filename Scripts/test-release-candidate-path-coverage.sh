#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

WORKFLOW="${1:-.github/workflows/release-candidate.yml}"
FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-candidate-path-coverage"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"

REAL_GREP="$(command -v grep)"
MISSING_WORKFLOW="$FIXTURE/missing-path-workflow.yml"
MISSING_OUTPUT="$FIXTURE/missing-path-output.log"

fail() {
  echo "Release candidate path coverage fixture failed: $*" >&2
  exit 1
}

REQUIRED_PATHS=(
  'App/SchneeGlass.entitlements'
)

validate_workflow_paths() {
  local workflow="$1"
  local paths_section="$FIXTURE/paths-section.txt"
  local sed_status=0
  local required_path=''
  local expected=''
  local count=''
  local awk_status=0

  [[ -f "$workflow" ]] || {
    echo "Release candidate path coverage validation failed: workflow is missing: $workflow" >&2
    return 1
  }

  if sed -n '
/^  pull_request:$/,/^[^ ]/ {
  /^    paths:$/,/^    [^ ]/p
}
' "$workflow" > "$paths_section"; then
    sed_status=0
  else
    sed_status=$?
  fi

  [[ "$sed_status" -eq 0 ]] || {
    echo "Release candidate path coverage validation failed: unable to enumerate pull_request.paths (sed status $sed_status)" >&2
    return 1
  }

  for required_path in "${REQUIRED_PATHS[@]}"; do
    expected="      - '$required_path'"
    if count="$(awk -v expected="$expected" '$0 == expected { count += 1 } END { print count + 0 }' "$paths_section")"; then
      awk_status=0
    else
      awk_status=$?
    fi

    [[ "$awk_status" -eq 0 ]] || {
      echo "Release candidate path coverage validation failed: unable to count pull_request.paths entry for $required_path (awk status $awk_status)" >&2
      return 1
    }
    [[ "$count" =~ ^[0-9]+$ ]] || {
      echo "Release candidate path coverage validation failed: pull_request path count is not numeric for $required_path: $count" >&2
      return 1
    }
    [[ "$count" == '1' ]] || {
      echo "Release candidate path coverage validation failed: expected exactly one pull_request path for $required_path; found $count" >&2
      return 1
    }
  done
}

validate_workflow_paths "$WORKFLOW" || fail "current workflow path coverage is invalid"

# Regression: every existing release-critical trigger must be part of the canonical
# REQUIRED_PATHS contract. The current contract intentionally starts incomplete so this
# test proves it can detect the missing protection before the fix is applied.
UNCOVERED_CRITICAL_PATHS=(
  '.github/workflows/release-candidate.yml'
  'Scripts/verify-xcode-version.sh'
  'Scripts/resolve-release-version.sh'
  'Scripts/test-release-candidate-version-extraction.sh'
  'Scripts/test-release-candidate-path-coverage.sh'
  'Scripts/verify-release-metadata.sh'
  'Scripts/verify-required-plist-value.sh'
  'App/Info.plist'
  'SchneeGlass.xcodeproj/project.pbxproj'
  'RELEASE.md'
)

for missing_path in "${UNCOVERED_CRITICAL_PATHS[@]}"; do
  "$REAL_GREP" -Fv \
    "      - '$missing_path'" \
    "$WORKFLOW" \
    > "$MISSING_WORKFLOW"

  if validate_workflow_paths "$MISSING_WORKFLOW" >"$MISSING_OUTPUT" 2>&1; then
    cat "$MISSING_OUTPUT"
    fail "unexpectedly accepted a workflow missing: $missing_path"
  fi

  "$REAL_GREP" -Fq \
    "Release candidate path coverage validation failed: expected exactly one pull_request path for $missing_path; found 0" \
    "$MISSING_OUTPUT"
done

rm -rf "$FIXTURE"
echo 'Release candidate path coverage fixture passed'
