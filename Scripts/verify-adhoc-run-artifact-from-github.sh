#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "GitHub ad-hoc artifact verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 3 ]] || fail 'usage: verify-adhoc-run-artifact-from-github.sh <run-id> <version> <expected-main-sha>'

RUN_ID="$1"
VERSION="$2"
SOURCE_SHA="$3"
[[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || fail 'run ID must be positive decimal'
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'version must be X.Y.Z'
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'source SHA must be lowercase 40-hex'

REPOSITORY='Lamy210/SchneeGlass'
ARTIFACT_NAME="SchneeGlass-$VERSION-adhoc-candidate"
GH_BIN="${GH_BIN:-gh}"
JQ_BIN="${JQ_BIN:-jq}"
command -v "$GH_BIN" >/dev/null 2>&1 || fail 'gh CLI is required'
command -v "$JQ_BIN" >/dev/null 2>&1 || fail 'jq is required'
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Reuse the canonical authenticated run identity + live main check. Do not
# assume that a successful PR event generated a publishable Actions artifact.
GH_BIN="$GH_BIN" JQ_BIN="$JQ_BIN" \
  bash "$ROOT/Scripts/verify-adhoc-run-from-github.sh" "$RUN_ID" >/dev/null \
  || fail 'candidate run provenance or live main check failed'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$GH_BIN" api "repos/$REPOSITORY/actions/runs/$RUN_ID" > "$TMP/run.json" \
  || fail 'unable to re-fetch candidate workflow run'
"$JQ_BIN" -e --arg repo "$REPOSITORY" --arg sha "$SOURCE_SHA" \
  --argjson id "$RUN_ID" '
  type == "object" and .id == $id and
  .repository.full_name == $repo and
  (.repository.id | type == "number" and . > 0 and floor == .) and
  .head_repository.id == .repository.id and
  .head_sha == $sha and .head_branch == "main" and
  .event == "workflow_dispatch" and .status == "completed" and
  .conclusion == "success" and .run_attempt == 1
' "$TMP/run.json" >/dev/null || fail 'candidate run changed or does not match expected main SHA'

REPOSITORY_ID="$("$JQ_BIN" -er '.repository.id' "$TMP/run.json")"

# Do not trust a single page, a user-supplied JSON file, or an artifact name
# without its authenticated workflow_run binding.
"$GH_BIN" api --paginate --slurp \
  "repos/$REPOSITORY/actions/runs/$RUN_ID/artifacts?per_page=100" > "$TMP/artifacts.json" \
  || fail 'unable to enumerate candidate workflow artifacts'

"$JQ_BIN" -e '
  type == "array" and length > 0 and
  all(.[]; type == "object" and
    (.total_count | type == "number" and . >= 0 and floor == .) and
    (.artifacts | type == "array")
  ) and
  ([.[].total_count] | unique | length) == 1 and
  ([.[] | .artifacts[]] | length) == .[0].total_count and
  ([.[] | .artifacts[] | .id] | length) ==
    ([.[] | .artifacts[] | .id] | unique | length)
' "$TMP/artifacts.json" >/dev/null \
  || fail 'artifact pagination or inventory is malformed/incomplete'

"$JQ_BIN" -e --arg name "$ARTIFACT_NAME" --arg sha "$SOURCE_SHA" \
  --argjson run "$RUN_ID" --argjson repo_id "$REPOSITORY_ID" '
  [ .[] | .artifacts[] | select(.name == $name) ] as $items |
  ($items | length) == 1 and
  ($items[0] |
    (.id | type == "number" and . > 0 and floor == .) and
    (.expired == false) and
    (.size_in_bytes | type == "number" and . > 0 and floor == .) and
    (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
    (.workflow_run.id == $run) and
    (.workflow_run.repository_id == $repo_id) and
    (.workflow_run.head_repository_id == $repo_id) and
    (.workflow_run.head_branch == "main") and
    (.workflow_run.head_sha == $sha)
  )
' "$TMP/artifacts.json" >/dev/null \
  || fail 'expected artifact missing, duplicated, expired or unbound from run'

# This is GitHub's digest for the outer Actions artifact ZIP, not the inner
# SchneeGlass app ZIP digest. The inner archive is verified separately.
"$JQ_BIN" -r --arg name "$ARTIFACT_NAME" '
  .[] | .artifacts[] | select(.name == $name) | "artifact_id=\(.id)\nartifact_digest=\(.digest)"
' "$TMP/artifacts.json"
