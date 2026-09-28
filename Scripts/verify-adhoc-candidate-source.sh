#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc candidate source verification failed: $*" >&2
  exit 1
}

EVENT_NAME="${1:-}"
REF_NAME="${2:-}"
EXPECTED_SHA="${3:-}"
CHECKOUT_SHA="${4:-}"

[[ "$EVENT_NAME" == 'pull_request' || "$EVENT_NAME" == 'workflow_dispatch' ]] \
  || fail "unsupported event: $EVENT_NAME"

[[ -n "$REF_NAME" ]] || fail "ref name is required"
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "GITHUB_SHA must be a lowercase 40-hex commit"
[[ "$CHECKOUT_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "checked-out HEAD must be a lowercase 40-hex commit"

[[ "$CHECKOUT_SHA" == "$EXPECTED_SHA" ]] \
  || fail "checked-out HEAD does not match GITHUB_SHA"

if [[ "$EVENT_NAME" == 'workflow_dispatch' ]]; then
  [[ "$REF_NAME" == 'main' ]] \
    || fail "manual ad-hoc candidates must run from main"
fi

echo "Ad-hoc candidate source verified: event=$EVENT_NAME ref=$REF_NAME sha=$CHECKOUT_SHA"
