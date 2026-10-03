#!/usr/bin/env bash
set -euo pipefail

WORKFLOW="${1:-.github/workflows/adhoc-release-candidate.yml}"

fail() {
  echo "Ad-hoc release path coverage fixture failed: $*" >&2
  exit 1
}

[[ -f "$WORKFLOW" ]] || fail "workflow is missing: $WORKFLOW"

require_exact_pull_request_path() {
  local path="$1"
  local expected="      - '$path'"
  local count

  count="$(awk -v expected="$expected" '$0 == expected { count += 1 } END { print count + 0 }' "$WORKFLOW")"
  [[ "$count" == '1' ]] \
    || fail "expected exactly one pull_request path for $path; found $count"
}

# The source plist carries release-critical bundle policy such as
# LSMultipleInstancesProhibited. A PR changing it must run the Ad-Hoc built-bundle
# validation instead of relying on unrelated workflow changes to trigger the job.
require_exact_pull_request_path 'App/Info.plist'

echo 'Ad-hoc release path coverage fixture passed'
