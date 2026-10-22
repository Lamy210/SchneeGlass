#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc candidate approval chain failed: $*" >&2
  exit 1
}

[[ "$#" -eq 8 ]] || fail 'usage: verify-adhoc-candidate-approval-chain.sh <run-id> <artifact-id> <version> <build> <source-sha> <owner-qa-comment-id> <downloaded-actions-zip> <new-output-directory>'

RUN_ID="$1"
EXPECTED_ARTIFACT_ID="$2"
VERSION="$3"
BUILD="$4"
SOURCE_SHA="$5"
QA_COMMENT_ID="$6"
OUTER_ZIP="$7"
OUTPUT_DIR="$8"

[[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || fail 'run ID must be positive decimal'
[[ "$EXPECTED_ARTIFACT_ID" =~ ^[1-9][0-9]*$ ]] || fail 'artifact ID must be positive decimal'
[[ "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail 'version must be strict X.Y.Z'
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'build must be positive decimal'
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'source SHA must be lowercase 40-hex'
[[ "$QA_COMMENT_ID" =~ ^[1-9][0-9]*$ ]] || fail 'owner QA comment ID must be positive decimal'
[[ -n "$OUTER_ZIP" && -n "$OUTPUT_DIR" ]] || fail 'input and output paths must not be empty'
[[ ! -e "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || fail 'output directory must be new; never overwrite'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
command -v shasum >/dev/null 2>&1 || fail 'shasum is required'

# The provider validates the exact run, current main, unique Actions artifact
# ID and outer ZIP digest against authenticated GitHub API responses.
resolve_artifact() {
  local response first second
  response="$(bash "$ROOT/Scripts/verify-adhoc-run-artifact-from-github.sh" \
    "$RUN_ID" "$VERSION" "$SOURCE_SHA")" \
    || fail 'authenticated Actions artifact or current main check failed'
  [[ "$response" == *$'\n'* ]] || fail 'malformed artifact verification response'
  first="${response%%$'\n'*}"
  second="${response#*$'\n'}"
  [[ "$second" != *$'\n'* ]] || fail 'extra artifact verification response fields'
  [[ "$first" =~ ^artifact_id=([1-9][0-9]*)$ ]] || fail 'malformed artifact ID response'
  [[ "${BASH_REMATCH[1]}" == "$EXPECTED_ARTIFACT_ID" ]] \
    || fail 'selected artifact ID does not match verified run'
  [[ "$second" =~ ^artifact_digest=(sha256:[0-9a-f]{64})$ ]] \
    || fail 'malformed artifact digest response'
  VERIFIED_OUTER_DIGEST="${BASH_REMATCH[1]}"
}

VERIFIED_OUTER_DIGEST=''
resolve_artifact
FIRST_DIGEST="$VERIFIED_OUTER_DIGEST"

# The existing extractor hashes the *same open file descriptor* used for
# extraction, enforces six flat entries, and creates only a new directory.
python3 "$ROOT/Scripts/extract-verified-adhoc-actions-archive.py" \
  "$OUTER_ZIP" "$FIRST_DIGEST" "$VERSION" "$OUTPUT_DIR" >/dev/null \
  || fail 'outer Actions ZIP verification or safe extraction failed'

# A successful outer ZIP digest does not authenticate the inner app archive.
bash "$ROOT/Scripts/verify-adhoc-candidate-artifact.sh" \
  "$OUTPUT_DIR" "$VERSION" "$BUILD" "$SOURCE_SHA" >/dev/null \
  || fail 'inner ad-hoc candidate metadata or checksum failed'

INNER_ZIP="$OUTPUT_DIR/SchneeGlass-$VERSION-adhoc-candidate.zip"
INNER_SHA="$(shasum -a 256 "$INNER_ZIP" | awk '{print $1}')"
[[ "$INNER_SHA" =~ ^[0-9a-f]{64}$ ]] || fail 'unable to calculate inner ZIP SHA-256'

# Only an exact, unedited owner-authored QA approval for the computed inner
# digest may pass. This verifier does not post comments on anyone's behalf.
bash "$ROOT/Scripts/verify-adhoc-qa-comment-from-github.sh" \
  "$QA_COMMENT_ID" "$RUN_ID" "$VERSION" "$BUILD" "$SOURCE_SHA" "$INNER_SHA" >/dev/null \
  || fail 'authenticated owner QA approval missing or mismatched'

# Re-read the live run/main/artifact state after local processing; the future
# publisher must independently repeat all relevant checks at mutation time.
resolve_artifact
[[ "$VERIFIED_OUTER_DIGEST" == "$FIRST_DIGEST" ]] \
  || fail 'Actions artifact digest changed during preflight'

echo "Ad-hoc candidate identity and authenticated owner QA verified (NOT publication authorization): run=$RUN_ID artifact=$EXPECTED_ARTIFACT_ID source=$SOURCE_SHA inner_zip_sha256=$INNER_SHA"
