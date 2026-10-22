#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Verified Actions artifact download failed: $*" >&2
  exit 1
}

[[ "$#" -eq 5 ]] || fail 'usage: download-verified-adhoc-actions-artifact.sh <run-id> <artifact-id> <version> <source-sha> <new-actions-zip-file>'

RUN_ID="$1"
ARTIFACT_ID="$2"
VERSION="$3"
SOURCE_SHA="$4"
DEST="$5"

[[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || fail 'run ID must be positive decimal'
[[ "$ARTIFACT_ID" =~ ^[1-9][0-9]*$ ]] || fail 'artifact ID must be positive decimal'
[[ "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail 'version must be X.Y.Z'
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'source SHA must be lowercase 40-hex'
[[ -n "$DEST" && "$DEST" != "/" ]] || fail 'destination must name a new file'
[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail 'destination exists; refusing to overwrite'

PARENT="$(dirname -- "$DEST")"
[[ -d "$PARENT" && ! -L "$PARENT" ]] || fail 'destination parent must be a real directory'
PARENT="$(cd -- "$PARENT" && pwd)"
DEST="$PARENT/$(basename -- "$DEST")"
[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail 'destination exists; refusing to overwrite'

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
GH_BIN="${GH_BIN:-gh}"
command -v "$GH_BIN" >/dev/null 2>&1 || fail 'gh CLI is required'
command -v shasum >/dev/null 2>&1 || fail 'shasum is required'

# The helper queries the authenticated run, live main and every artifact page.
# It selects exactly one non-expired artifact and validates the run binding.
resolve_digest() {
  local response first second
  response="$(bash "$ROOT/Scripts/verify-adhoc-run-artifact-from-github.sh" \
    "$RUN_ID" "$VERSION" "$SOURCE_SHA")" \
    || fail 'authenticated run/artifact provenance check failed'
  [[ "$response" == *$'\n'* ]] || fail 'malformed artifact identity response'
  first="${response%%$'\n'*}"
  second="${response#*$'\n'}"
  [[ "$second" != *$'\n'* ]] || fail 'extra artifact identity fields'
  [[ "$first" == "artifact_id=$ARTIFACT_ID" ]] \
    || fail 'requested artifact ID differs from the verified run artifact'
  [[ "$second" =~ ^artifact_digest=sha256:([0-9a-f]{64})$ ]] \
    || fail 'malformed authenticated artifact digest'
  VERIFIED_DIGEST="${BASH_REMATCH[1]}"
}

VERIFIED_DIGEST=''
resolve_digest
FIRST_DIGEST="$VERIFIED_DIGEST"

# The GitHub REST artifact-by-ID ZIP endpoint redirects to a short-lived
# archive URL; gh api follows that redirect and streams the binary response.
# Do not use gh run download: it extracts archives without this outer digest
# and exact-ID validation.
STAGE="$(mktemp "$PARENT/.schneeglass-actions-zip.XXXXXXXX")" \
  || fail 'unable to create private download stage'
cleanup() {
  [[ -z "${STAGE:-}" ]] || rm -f -- "$STAGE"
}
trap cleanup EXIT

"$GH_BIN" api "repos/Lamy210/SchneeGlass/actions/artifacts/$ARTIFACT_ID/zip" \
  > "$STAGE" || fail 'GitHub artifact ZIP download failed'

[[ -f "$STAGE" && ! -L "$STAGE" && -s "$STAGE" ]] \
  || fail 'downloaded artifact is empty or not a regular file'
SIZE="$(wc -c < "$STAGE" | tr -d '[:space:]')"
[[ "$SIZE" =~ ^[1-9][0-9]*$ && "$SIZE" -le 1073741824 ]] \
  || fail 'downloaded artifact exceeds the 1 GiB limit'

DOWNLOADED_DIGEST="$(shasum -a 256 "$STAGE" | awk '{print $1}')" \
  || fail 'unable to hash downloaded artifact'
[[ "$DOWNLOADED_DIGEST" == "$FIRST_DIGEST" ]] \
  || fail 'downloaded Actions ZIP does not match authenticated GitHub SHA-256'

# A second API read rejects an artifact deleted/replaced or main moved while
# the download was in progress. A later publisher must recheck before writes.
resolve_digest
[[ "$VERIFIED_DIGEST" == "$FIRST_DIGEST" ]] \
  || fail 'authenticated artifact digest changed during download'

[[ ! -e "$DEST" && ! -L "$DEST" ]] || fail 'destination became occupied'
# The stage and destination share a filesystem. Hard-link creation fails if
# DEST exists (including a symlink); never use mv -f or gh --clobber.
ln "$STAGE" "$DEST" || fail 'unable to create new artifact destination safely'
rm -f -- "$STAGE"
STAGE=''

echo "Exact-ID Actions artifact downloaded and verified: run=$RUN_ID artifact=$ARTIFACT_ID sha256:$FIRST_DIGEST file=$DEST"
