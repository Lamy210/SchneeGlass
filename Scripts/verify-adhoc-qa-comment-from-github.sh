#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Authenticated ad-hoc QA comment verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 6 ]] || fail 'usage: verify-adhoc-qa-comment-from-github.sh <comment-id> <run-id> <version> <build> <source-sha> <inner-zip-sha256>'

COMMENT_ID="$1"
RUN_ID="$2"
VERSION="$3"
BUILD="$4"
SOURCE_SHA="$5"
ARCHIVE_SHA="$6"

[[ "$COMMENT_ID" =~ ^[1-9][0-9]*$ ]] || fail 'comment ID must be positive decimal'
[[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || fail 'run ID must be positive decimal'
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'version must be strict X.Y.Z'
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'build must be positive decimal'
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'source SHA must be lowercase 40-hex'
[[ "$ARCHIVE_SHA" =~ ^[0-9a-f]{64}$ ]] || fail 'inner ZIP SHA-256 must be lowercase 64-hex'

REPO='Lamy210/SchneeGlass'
ISSUE_URL="https://api.github.com/repos/$REPO/issues/520"
GH_BIN="${GH_BIN:-gh}"
JQ_BIN="${JQ_BIN:-jq}"
command -v "$GH_BIN" >/dev/null 2>&1 || fail 'gh CLI is required'
command -v "$JQ_BIN" >/dev/null 2>&1 || fail 'jq is required'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Both API resources must be fetched directly through the authenticated
# GitHub CLI; user-supplied JSON and claimed reviewer names are not inputs.
"$GH_BIN" api "repos/$REPO" > "$TMP/repository.json" \
  || fail 'unable to fetch authenticated repository identity'
"$GH_BIN" api "repos/$REPO/issues/comments/$COMMENT_ID" > "$TMP/comment.json" \
  || fail 'unable to fetch authenticated QA comment'

"$JQ_BIN" -e --arg repo "$REPO" '
  type == "object" and .full_name == $repo and
  .id == 1359347782 and .owner.login == "Lamy210" and
  .owner.id == 90091196 and .owner.type == "User"
' "$TMP/repository.json" >/dev/null \
  || fail 'repository or release-authority identity is unexpected'

"$JQ_BIN" -e --arg url "$ISSUE_URL" --argjson id "$COMMENT_ID" \
  --argjson owner_id 90091196 '
  type == "object" and
  .id == $id and .issue_url == $url and
  .author_association == "OWNER" and
  .user.id == $owner_id and .user.login == "Lamy210" and
  .user.type == "User" and
  (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
  .updated_at == .created_at and
  (.body | type == "string")
' "$TMP/comment.json" >/dev/null \
  || fail 'QA comment is edited, not issue #520, or not from the repository owner'

# A fixed, unambiguous schema prevents a general status comment, partial
# match, Markdown quotation, repeated key or embedded text from being treated
# as an explicit candidate approval. The comment must be posted manually by
# the trusted repository owner; this script never creates an approval.
EXPECTED="$(printf 'SCHNEEGLASS_ADHOC_QA_APPROVAL_V1\nrun_id=%s\nrun_attempt=1\nsource_sha=%s\nversion=%s\nbuild=%s\narchive_sha256=%s\nqa_result=pass' \
  "$RUN_ID" "$SOURCE_SHA" "$VERSION" "$BUILD" "$ARCHIVE_SHA")"

"$JQ_BIN" -e --arg expected "$EXPECTED" '
  .body == $expected or .body == ($expected + "\n")
' "$TMP/comment.json" >/dev/null \
  || fail 'QA approval fields do not exactly match the candidate'

CREATED_AT="$("$JQ_BIN" -er '.created_at' "$TMP/comment.json")"
echo "Verified GitHub owner QA approval comment ID=$COMMENT_ID run=$RUN_ID source=$SOURCE_SHA inner_zip_sha256=$ARCHIVE_SHA approved_at=$CREATED_AT"
