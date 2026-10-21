#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "GitHub ad-hoc candidate provenance verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail 'usage: verify-adhoc-run-from-github.sh <candidate-run-id>'
RUN_ID="$1"
[[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || fail 'run ID must be a positive decimal integer'

REPOSITORY='Lamy210/SchneeGlass'
GH_BIN="${GH_BIN:-gh}"
JQ_BIN="${JQ_BIN:-jq}"

command -v "$GH_BIN" >/dev/null 2>&1 || fail 'gh CLI is required'
command -v "$JQ_BIN" >/dev/null 2>&1 || fail 'jq is required'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PROVENANCE_CHECK="$ROOT/Scripts/verify-adhoc-publication-candidate.sh"
[[ -f "$PROVENANCE_CHECK" ]] || fail 'canonical candidate metadata validator missing'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
RUN_JSON="$TMP/run.json"
MAIN_JSON="$TMP/main.json"

# Fetch once per endpoint. Never accept user-supplied JSON as the source of truth.
"$GH_BIN" api "repos/$REPOSITORY/actions/runs/$RUN_ID" > "$RUN_JSON" \
  || fail 'unable to fetch authenticated GitHub workflow run'
"$GH_BIN" api "repos/$REPOSITORY/branches/main" > "$MAIN_JSON" \
  || fail 'unable to fetch live GitHub main'

"$JQ_BIN" -e --arg repo "$REPOSITORY" --argjson run_id "$RUN_ID" '
  type == "object" and
  (.id == $run_id) and
  (.repository.full_name == $repo) and
  (.head_repository.full_name == $repo) and
  (.head_repository.id == .repository.id) and
  (.workflow_id == 369218665) and
  (.run_attempt | type == "number" and . >= 1 and floor == .) and
  ([.name, .path, .event, .status, .conclusion, .head_branch, .head_sha] |
   all(.[]; type == "string" and length > 0))
' "$RUN_JSON" >/dev/null || fail 'GitHub run identity or metadata is malformed'

"$JQ_BIN" -e '
  type == "object" and
  .name == "main" and
  (.commit.sha | type == "string" and test("^[0-9a-f]{40}$"))
' "$MAIN_JSON" >/dev/null || fail 'live main metadata is malformed'

field() {
  "$JQ_BIN" -er --arg k "$1" '.[$k]' "$RUN_JSON"
}

WORKFLOW_NAME="$(field name)"
WORKFLOW_PATH="$(field path)"
EVENT_NAME="$(field event)"
STATUS="$(field status)"
CONCLUSION="$(field conclusion)"
HEAD_BRANCH="$(field head_branch)"
HEAD_SHA="$(field head_sha)"
ATTEMPT="$(field run_attempt)"
MAIN_SHA="$("$JQ_BIN" -er '.commit.sha' "$MAIN_JSON")"

bash "$PROVENANCE_CHECK" \
  "$WORKFLOW_NAME" \
  "$WORKFLOW_PATH" \
  "$EVENT_NAME" \
  "$STATUS" \
  "$CONCLUSION" \
  "$HEAD_BRANCH" \
  "$HEAD_SHA" \
  "$ATTEMPT" \
  "$MAIN_SHA" || fail 'GitHub run is not an eligible exact-main ad-hoc candidate'

echo "Authenticated GitHub run metadata matches current main: run=$RUN_ID sha=$HEAD_SHA"
