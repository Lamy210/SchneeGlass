#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc release slot verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail 'usage: verify-adhoc-release-slot.sh <vX.Y.Z>'
TAG="$1"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'tag must be vX.Y.Z'

REPOSITORY='Lamy210/SchneeGlass'
GH_BIN="${GH_BIN:-gh}"
JQ_BIN="${JQ_BIN:-jq}"
command -v "$GH_BIN" >/dev/null 2>&1 || fail 'gh CLI is required'
command -v "$JQ_BIN" >/dev/null 2>&1 || fail 'jq is required'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A release may have been created without a currently resolvable Git tag,
# and a lightweight tag may exist without any Release. Both are collisions.
# gh --paginate --slurp is required; a single page is not a complete inventory.
"$GH_BIN" api --paginate --slurp \
  "repos/$REPOSITORY/releases?per_page=100" > "$TMP/releases.json" \
  || fail 'unable to enumerate all GitHub Releases'
"$GH_BIN" api --paginate --slurp \
  "repos/$REPOSITORY/git/matching-refs/tags/$TAG?per_page=100" > "$TMP/tags.json" \
  || fail 'unable to enumerate matching Git tags'

"$JQ_BIN" -e '
  type == "array" and
  length > 0 and
  all(.[]; type == "array" and
    all(.[]; type == "object" and
      (.id | type == "number" and . > 0) and
      (.tag_name | type == "string" and length > 0) and
      (.draft | type == "boolean")
    )
  )
' "$TMP/releases.json" >/dev/null || fail 'malformed paginated Release inventory'

"$JQ_BIN" -e '
  type == "array" and
  length > 0 and
  all(.[]; type == "array" and
    all(.[]; type == "object" and
      (.ref | type == "string" and startswith("refs/tags/")) and
      (.object.sha | type == "string" and test("^[0-9a-f]{40}$"))
    )
  )
' "$TMP/tags.json" >/dev/null || fail 'malformed paginated Git tag inventory'

"$JQ_BIN" -e --arg tag "$TAG" '
  all(.[][]; .tag_name != $tag)
' "$TMP/releases.json" >/dev/null || fail "Release already uses target tag: $TAG"

"$JQ_BIN" -e --arg ref "refs/tags/$TAG" '
  all(.[][]; .ref != $ref)
' "$TMP/tags.json" >/dev/null || fail "Git tag already exists: $TAG"

echo "Ad-hoc release tag slot is unoccupied at verification time: $TAG"
