#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

WORKFLOW="${1:-.github/workflows/adhoc-release-candidate.yml}"
FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-adhoc-release-path-coverage"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"

REAL_GREP="$(command -v grep)"
MISSING_WORKFLOW="$FIXTURE/missing-path-workflow.yml"
MISSING_OUTPUT="$FIXTURE/missing-path-output.log"

fail() {
  echo "Ad-hoc release path coverage fixture failed: $*" >&2
  exit 1
}

REQUIRED_PATHS=(
  '.github/workflows/adhoc-release-candidate.yml'
  'Scripts/build-adhoc-release-candidate.sh'
  'Scripts/verify-adhoc-signature-details.sh'
  'Scripts/test-adhoc-signature-details.sh'
  'Scripts/verify-adhoc-candidate-source.sh'
  'Scripts/test-adhoc-candidate-source.sh'
  'Scripts/test-adhoc-release-single-instance-bundle-policy.sh'
  'Scripts/test-adhoc-release-path-coverage.sh'
  'Scripts/test-adhoc-release-path-coverage-scope.sh'
  'Scripts/resolve-release-version.sh'
  'Scripts/verify-release-metadata.sh'
  'Scripts/verify-required-plist-value.sh'
  'Scripts/verify-optional-release-entitlements.sh'
  'Scripts/verify-xcode-version.sh'
  'App/Info.plist'
  'App/SchneeGlass.entitlements'
  'SchneeGlass.xcodeproj/project.pbxproj'
  'SchneeGlass.xcodeproj/xcshareddata/xcschemes/SchneeGlass.xcscheme'
  'RELEASE.md'
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
    echo "Ad-hoc release path coverage validation failed: workflow is missing: $workflow" >&2
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
    echo "Ad-hoc release path coverage validation failed: unable to enumerate pull_request.paths (sed status $sed_status)" >&2
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
      echo "Ad-hoc release path coverage validation failed: unable to count pull_request.paths entry for $required_path (awk status $awk_status)" >&2
      return 1
    }
    [[ "$count" =~ ^[0-9]+$ ]] || {
      echo "Ad-hoc release path coverage validation failed: pull_request path count is not numeric for $required_path: $count" >&2
      return 1
    }
    [[ "$count" == '1' ]] || {
      echo "Ad-hoc release path coverage validation failed: expected exactly one pull_request path for $required_path; found $count" >&2
      return 1
    }
  done
}

validate_workflow_paths "$WORKFLOW" || fail "current workflow path coverage is invalid"

# Regression: remove every current release-critical trigger one at a time. The canonical
# required set must reject each synthetic workflow so future trigger deletions cannot remain green.
for missing_path in "${REQUIRED_PATHS[@]}"; do
  "$REAL_GREP" -Fv \
    "      - '$missing_path'" \
    "$WORKFLOW" \
    > "$MISSING_WORKFLOW"

  if validate_workflow_paths "$MISSING_WORKFLOW" >"$MISSING_OUTPUT" 2>&1; then
    cat "$MISSING_OUTPUT"
    fail "unexpectedly accepted a workflow missing: $missing_path"
  fi

  "$REAL_GREP" -Fq \
    "Ad-hoc release path coverage validation failed: expected exactly one pull_request path for $missing_path; found 0" \
    "$MISSING_OUTPUT"
done

rm -rf "$FIXTURE"
echo 'Ad-hoc release path coverage fixture passed'
