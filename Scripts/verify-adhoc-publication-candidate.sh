#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc publication candidate verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 9 ]] || fail 'usage: verify-adhoc-publication-candidate.sh <workflow-name> <workflow-path> <event> <status> <conclusion> <branch> <candidate-sha> <attempt> <current-main-sha>'

WORKFLOW_NAME="$1"
WORKFLOW_PATH="$2"
EVENT_NAME="$3"
RUN_STATUS="$4"
RUN_CONCLUSION="$5"
HEAD_BRANCH="$6"
HEAD_SHA="$7"
RUN_ATTEMPT="$8"
CURRENT_MAIN_SHA="$9"

[[ "$WORKFLOW_NAME" == 'Ad-Hoc Release Candidate' ]] || fail 'wrong workflow name'
[[ "$WORKFLOW_PATH" == '.github/workflows/adhoc-release-candidate.yml' ]] || fail 'wrong workflow path'
[[ "$EVENT_NAME" == 'workflow_dispatch' ]] || fail 'candidate must be manually dispatched'
[[ "$RUN_STATUS" == 'completed' ]] || fail 'candidate run is not completed'
[[ "$RUN_CONCLUSION" == 'success' ]] || fail 'candidate run did not succeed'
[[ "$HEAD_BRANCH" == 'main' ]] || fail 'candidate run must target main'
[[ "$HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'candidate head SHA is malformed'
[[ "$RUN_ATTEMPT" == '1' ]] || fail 'candidate must be a first-attempt workflow run'
[[ "$CURRENT_MAIN_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'current main SHA is malformed'
[[ "$HEAD_SHA" == "$CURRENT_MAIN_SHA" ]] || fail 'candidate is stale relative to current main'

printf 'Ad-hoc publication candidate metadata verified: %s\n' "$HEAD_SHA"
