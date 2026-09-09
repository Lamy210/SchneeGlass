#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Production candidate run validation failed: $*" >&2
  exit 1
}

RUN_NAME="${1:-}"
RUN_PATH="${2:-}"
RUN_EVENT="${3:-}"
RUN_STATUS="${4:-}"
RUN_CONCLUSION="${5:-}"
RUN_BRANCH="${6:-}"
RUN_HEAD_SHA="${7:-}"

[[ "$RUN_NAME" == 'Production Release Candidate' ]] \
  || fail "unexpected workflow name: $RUN_NAME"
[[ "$RUN_PATH" == '.github/workflows/production-release.yml' ]] \
  || fail "unexpected workflow path: $RUN_PATH"
[[ "$RUN_EVENT" == 'workflow_dispatch' ]] \
  || fail "candidate run must be workflow_dispatch"
[[ "$RUN_STATUS" == 'completed' ]] \
  || fail "candidate run status must be completed: $RUN_STATUS"
[[ "$RUN_CONCLUSION" == 'success' ]] \
  || fail "candidate run conclusion must be success: $RUN_CONCLUSION"
[[ "$RUN_BRANCH" == 'main' ]] \
  || fail "candidate run must be built from main: $RUN_BRANCH"
[[ "$RUN_HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "candidate run returned an invalid head SHA: $RUN_HEAD_SHA"

echo "Production candidate run OK: path=$RUN_PATH commit=$RUN_HEAD_SHA"
