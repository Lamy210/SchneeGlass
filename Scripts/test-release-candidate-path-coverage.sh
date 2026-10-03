#!/usr/bin/env bash
set -euo pipefail

WORKFLOW="${1:-.github/workflows/release-candidate.yml}"

fail() {
  echo "Release candidate path coverage fixture failed: $*" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail "workflow is missing: $WORKFLOW"

PATHS_SECTION="$(mktemp)"
cleanup() {
  rm -f "$PATHS_SECTION"
}
trap cleanup EXIT

set +e
sed -n '
/^  pull_request:$/,/^[^ ]/ {
  /^    paths:$/,/^    [^ ]/p
}
' "$WORKFLOW" > "$PATHS_SECTION"
SED_STATUS=$?
set -e

[[ "$SED_STATUS" -eq 0 ]] \
  || fail "unable to enumerate pull_request.paths (sed status $SED_STATUS)"

require_exact_pull_request_path() {
  local path="$1"
  local expected="      - '$path'"
  local count
  local awk_status

  set +e
  count="$(awk -v expected="$expected" '$0 == expected { count += 1 } END { print count + 0 }' "$PATHS_SECTION")"
  awk_status=$?
  set -e

  [[ "$awk_status" -eq 0 ]] \
    || fail "unable to count pull_request.paths entry for $path (awk status $awk_status)"
  [[ "$count" =~ ^[0-9]+$ ]] \
    || fail "pull_request path count is not numeric for $path: $count"
  [[ "$count" == '1' ]] \
    || fail "expected exactly one pull_request path for $path; found $count"
}

# The unsigned candidate explicitly validates the source entitlements and sandbox policy.
# An entitlement-only PR must therefore run this workflow instead of skipping the
# release-candidate bundle baseline.
require_exact_pull_request_path 'App/SchneeGlass.entitlements'

echo 'Release candidate path coverage fixture passed'
