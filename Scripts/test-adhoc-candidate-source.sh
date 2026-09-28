#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

VALID_SHA='0123456789abcdef0123456789abcdef01234567'
OTHER_SHA='89abcdef0123456789abcdef0123456789abcdef'

bash Scripts/verify-adhoc-candidate-source.sh \
  workflow_dispatch \
  main \
  "$VALID_SHA" \
  "$VALID_SHA"

bash Scripts/verify-adhoc-candidate-source.sh \
  pull_request \
  341/merge \
  "$VALID_SHA" \
  "$VALID_SHA"

expect_failure() {
  local label="$1"
  shift
  if "$@" >/tmp/schneeglass-adhoc-source-failure.log 2>&1; then
    cat /tmp/schneeglass-adhoc-source-failure.log
    echo "Ad-hoc source verifier unexpectedly accepted: $label" >&2
    exit 1
  fi
}

expect_failure \
  'manual feature branch' \
  bash Scripts/verify-adhoc-candidate-source.sh \
    workflow_dispatch \
    feature/test \
    "$VALID_SHA" \
    "$VALID_SHA"
grep -Fq 'manual ad-hoc candidates must run from main' \
  /tmp/schneeglass-adhoc-source-failure.log

expect_failure \
  'checkout mismatch' \
  bash Scripts/verify-adhoc-candidate-source.sh \
    workflow_dispatch \
    main \
    "$VALID_SHA" \
    "$OTHER_SHA"
grep -Fq 'checked-out HEAD does not match GITHUB_SHA' \
  /tmp/schneeglass-adhoc-source-failure.log

expect_failure \
  'unsupported event' \
  bash Scripts/verify-adhoc-candidate-source.sh \
    push \
    main \
    "$VALID_SHA" \
    "$VALID_SHA"
grep -Fq 'unsupported event' /tmp/schneeglass-adhoc-source-failure.log

expect_failure \
  'malformed expected sha' \
  bash Scripts/verify-adhoc-candidate-source.sh \
    workflow_dispatch \
    main \
    deadbeef \
    "$VALID_SHA"
grep -Fq 'GITHUB_SHA must be a lowercase 40-hex commit' \
  /tmp/schneeglass-adhoc-source-failure.log

rm -f /tmp/schneeglass-adhoc-source-failure.log
echo 'Ad-hoc candidate source fixtures passed'
