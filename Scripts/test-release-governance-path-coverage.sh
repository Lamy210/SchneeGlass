#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

WORKFLOW="${1:-.github/workflows/release-governance-setup.yml}"
FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-governance-path-coverage"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"

REAL_GREP="$(command -v grep)"
MISSING_WORKFLOW="$FIXTURE/missing-path-workflow.yml"
MISSING_OUTPUT="$FIXTURE/missing-path-output.log"

fail() {
  echo "Release Governance path coverage fixture failed: $*" >&2
  exit 1
}

REQUIRED_PATHS=(
  '.github/workflows/release-governance-setup.yml'
  '.github/rulesets/main-release-governance.json'
  'Scripts/setup-release-governance.sh'
  'Scripts/setup-production-release-environment.sh'
  'Scripts/verify-production-release-readiness.sh'
  'Scripts/test-verify-production-release-readiness.sh'
  'Scripts/verify-local-release-source.sh'
  'Scripts/test-verify-local-release-source.sh'
  'Scripts/verify-release-canonical-ruleset.sh'
  'Scripts/test-setup-release-governance.sh'
  'Scripts/test-release-governance-path-coverage.sh'
  'Scripts/verify-release-branch-protection.sh'
  'Scripts/verify-release-required-branch-rules.sh'
  'Scripts/verify-release-required-checks.sh'
  'docs/REPOSITORY_GOVERNANCE.md'
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
    echo "Release Governance path coverage validation failed: workflow is missing: $workflow" >&2
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
    echo "Release Governance path coverage validation failed: unable to enumerate pull_request.paths (sed status $sed_status)" >&2
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
      echo "Release Governance path coverage validation failed: unable to count pull_request.paths entry for $required_path (awk status $awk_status)" >&2
      return 1
    }
    [[ "$count" =~ ^[0-9]+$ ]] || {
      echo "Release Governance path coverage validation failed: pull_request path count is not numeric for $required_path: $count" >&2
      return 1
    }
    [[ "$count" == '1' ]] || {
      echo "Release Governance path coverage validation failed: expected exactly one pull_request path for $required_path; found $count" >&2
      return 1
    }
  done
}

validate_workflow_paths "$WORKFLOW" || fail "current workflow path coverage is invalid"

# Remove every protected trigger one at a time. Every synthetic workflow must fail closed,
# so future trigger deletions cannot leave the specialized governance safety integration green.
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
    "Release Governance path coverage validation failed: expected exactly one pull_request path for $missing_path; found 0" \
    "$MISSING_OUTPUT"
done

rm -rf "$FIXTURE"
echo 'Release Governance path coverage fixture passed'
