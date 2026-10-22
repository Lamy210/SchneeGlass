#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Authenticated ad-hoc public history failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail 'usage: materialize-authenticated-adhoc-release-history.sh <new-output-directory>'
DEST="$1"
[[ -n "$DEST" && "$DEST" != "/" ]] || fail 'output path must name a new directory'
[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail 'output directory already exists (no overwrite)'
PARENT="$(dirname -- "$DEST")"
[[ -d "$PARENT" && ! -L "$PARENT" ]] || fail 'output parent must be an existing real directory'
PARENT="$(cd -- "$PARENT" && pwd)"
DEST="$PARENT/$(basename -- "$DEST")"

command -v gh >/dev/null 2>&1 || fail 'gh CLI is required'
command -v jq >/dev/null 2>&1 || fail 'jq is required'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY='Lamy210/SchneeGlass'

STAGE="$(mktemp -d "$PARENT/.schneeglass-public-history.XXXXXXXX")" \
  || fail 'unable to create private staging directory'
cleanup() {
  if [[ -n "$STAGE" && -d "$STAGE" ]]; then
    rm -rf -- "$STAGE"
  fi
}
trap cleanup EXIT

# GitHub CLI paginates every page and slurps them as an array of JSON arrays.
# No user-provided tag list, release JSON, or unauthenticated history is accepted.
gh api --paginate --slurp "repos/$REPOSITORY/releases?per_page=100" \
  > "$STAGE/release-inventory.json" \
  || fail 'unable to enumerate public Releases from GitHub'

jq -e '
  type == "array" and length > 0 and
  all(.[]; type == "array" and
    all(.[]; type == "object" and
      (.id | type == "number" and . > 0 and floor == .) and
      (.tag_name | type == "string" and length > 0) and
      (.draft | type == "boolean")
    )
  )
' "$STAGE/release-inventory.json" >/dev/null \
  || fail 'GitHub Release page inventory is malformed'

jq -e '
  ([.[][] | .id] | length) == ([.[][] | .id] | unique | length) and
  ([.[][] | select(.draft == false) | .tag_name] | length) ==
    ([.[][] | select(.draft == false) | .tag_name] | unique | length) and
  all(.[][] | select(.draft == false);
    (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))
  )
' "$STAGE/release-inventory.json" >/dev/null \
  || fail 'published Releases contain duplicate IDs/tags or an unsupported public tag'

jq -r '.[][] | select(.draft == false) | .tag_name' \
  "$STAGE/release-inventory.json" | LC_ALL=C sort > "$STAGE/published-tags.txt" \
  || fail 'unable to materialize complete published tag list'

EXPECTED="$(jq '[.[][] | select(.draft == false)] | length' "$STAGE/release-inventory.json")"
[[ "$EXPECTED" =~ ^[0-9]+$ ]] || fail 'published Release count is invalid'

# This repository already shipped public v0.1.x Releases. A supposedly empty
# GitHub response is not evidence of first publication. Compare against the
# checked-in legacy manifest before trusting the fetched history snapshot.
LEGACY_MANIFEST="$ROOT/docs/release-history/legacy-public-releases.tsv"
[[ -f "$LEGACY_MANIFEST" ]] || fail 'checked-in known public Release manifest missing'
BASELINE_COUNT=0
while IFS=
if [[ "$EXPECTED" -gt 0 ]]; then
  (
    cd "$ROOT"
    bash Scripts/materialize-public-release-build-history.sh \
      "$REPOSITORY" "$STAGE/published-tags.txt" "$STAGE/history" \
      docs/release-history/legacy-public-releases.tsv
  ) || fail 'published Release history could not be fully materialized'

  i=1
  while [[ "$i" -le "$EXPECTED" ]]; do
    [[ -f "$STAGE/history/$i/RELEASE_EVIDENCE.txt" \
       && ! -L "$STAGE/history/$i/RELEASE_EVIDENCE.txt" ]] \
      || fail "missing verified public build evidence at history index $i"
    i=$((i + 1))
  done
fi

# Preserve the complete inventory and tag list as an auditable snapshot.
# Never touch an already-existing destination; this remains an offline,
# read-only GitHub history acquisition step rather than a publisher.
[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail 'output destination became occupied'
mv -- "$STAGE" "$DEST" || fail 'unable to finalize verified history snapshot'
STAGE=''
echo "Authenticated public Release history snapshot created: $DEST ($EXPECTED published Releases)"
\\t' read -r tag _; do
  [[ -n "$tag" && "$tag" != \\#* ]] || continue
  [[ "$tag" =~ ^v[0-9]+\\.[0-9]+\\.[0-9]+$ ]] \\
    || fail "malformed known public Release tag: $tag"
  grep -Fxq -- "$tag" "$STAGE/published-tags.txt" \\
    || fail "known public Release missing from GitHub inventory: $tag"
  BASELINE_COUNT=$((BASELINE_COUNT + 1))
done < "$LEGACY_MANIFEST"
[[ "$BASELINE_COUNT" -gt 0 ]] || fail 'known public Release manifest is empty'

mkdir "$STAGE/history"
if [[ "$EXPECTED" -gt 0 ]]; then
  (
    cd "$ROOT"
    bash Scripts/materialize-public-release-build-history.sh \
      "$REPOSITORY" "$STAGE/published-tags.txt" "$STAGE/history" \
      docs/release-history/legacy-public-releases.tsv
  ) || fail 'published Release history could not be fully materialized'

  i=1
  while [[ "$i" -le "$EXPECTED" ]]; do
    [[ -f "$STAGE/history/$i/RELEASE_EVIDENCE.txt" \
       && ! -L "$STAGE/history/$i/RELEASE_EVIDENCE.txt" ]] \
      || fail "missing verified public build evidence at history index $i"
    i=$((i + 1))
  done
fi

# Preserve the complete inventory and tag list as an auditable snapshot.
# Never touch an already-existing destination; this remains an offline,
# read-only GitHub history acquisition step rather than a publisher.
[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail 'output destination became occupied'
mv -- "$STAGE" "$DEST" || fail 'unable to finalize verified history snapshot'
STAGE=''
echo "Authenticated public Release history snapshot created: $DEST ($EXPECTED published Releases)"
