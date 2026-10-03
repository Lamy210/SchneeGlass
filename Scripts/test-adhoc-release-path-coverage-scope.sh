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

# A same-indented value outside pull_request.paths must not satisfy path coverage.
cat > "$SCOPE_WORKFLOW" <<'EOF'
name: Synthetic ad-hoc path-scope fixture

on:
  pull_request:
    paths:
      - '.github/workflows/adhoc-release-candidate.yml'
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

rm -rf "$FIXTURE"
echo 'Ad-hoc release path-coverage scope fixture passed'
