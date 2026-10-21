#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc QA evidence verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 7 ]] || fail 'usage: verify-adhoc-qa-evidence.sh <artifact-dir> <qa-evidence-file> <expected-version> <expected-build> <expected-source-sha> <expected-run-id> <expected-reviewer>'

ARTIFACT_DIR="$1"
EVIDENCE_FILE="$2"
VERSION="$3"
BUILD="$4"
SOURCE_SHA="$5"
RUN_ID="$6"
REVIEWER="$7"

[[ -f "$EVIDENCE_FILE" && ! -L "$EVIDENCE_FILE" && -s "$EVIDENCE_FILE" ]] || fail 'QA evidence must be a nonempty regular file, not a symlink'
[[ "$RUN_ID" =~ ^[1-9][0-9]*$ ]] || fail 'expected run id must be a positive decimal'
[[ "$REVIEWER" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,37}$ ]] || fail 'expected reviewer must be a GitHub login'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/verify-adhoc-candidate-artifact.sh" \
  "$ARTIFACT_DIR" "$VERSION" "$BUILD" "$SOURCE_SHA" >/dev/null \
  || fail 'candidate artifact validation failed'

ARCHIVE="$ARTIFACT_DIR/SchneeGlass-$VERSION-adhoc-candidate.zip"
ACTUAL_DIGEST="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_DIGEST" =~ ^[0-9a-f]{64}$ ]] || fail 'archive SHA-256 could not be calculated'

# A strictly parsed evidence record cannot elevate itself to an authenticated review.
# The future publisher must fetch the reviewer approval from a trusted GitHub identity
# source and supply independently obtained expected values to this verifier.
seen='|'
count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" == *=* ]] || fail 'malformed QA evidence line'
  key="${line%%=*}"
  value="${line#*=}"
  case "$key" in
    schema_version|candidate_run_id|candidate_run_attempt|candidate_source_commit|candidate_version|candidate_build|candidate_archive_sha256|qa_result|reviewed_by|reviewed_at) ;;
    *) fail "unknown QA evidence field: $key" ;;
  esac
  [[ "$seen" != *"|$key|"* ]] || fail "duplicate QA evidence field: $key"
  [[ -n "$value" ]] || fail "empty QA evidence field: $key"
  seen+="$key|"
  case "$key" in
    schema_version) [[ "$value" == '1' ]] || fail 'unsupported QA schema' ;;
    candidate_run_id) [[ "$value" == "$RUN_ID" ]] || fail 'QA candidate run id mismatch' ;;
    candidate_run_attempt) [[ "$value" == '1' ]] || fail 'QA must bind first run attempt' ;;
    candidate_source_commit) [[ "$value" == "$SOURCE_SHA" ]] || fail 'QA source commit mismatch' ;;
    candidate_version) [[ "$value" == "$VERSION" ]] || fail 'QA candidate version mismatch' ;;
    candidate_build) [[ "$value" == "$BUILD" ]] || fail 'QA candidate build mismatch' ;;
    candidate_archive_sha256)
      [[ "$value" =~ ^[0-9a-f]{64}$ ]] || fail 'QA archive digest is malformed'
      [[ "$value" == "$ACTUAL_DIGEST" ]] || fail 'QA archive digest mismatch'
      ;;
    qa_result) [[ "$value" == 'pass' ]] || fail 'QA result must be pass' ;;
    reviewed_by) [[ "$value" == "$REVIEWER" ]] || fail 'QA reviewer mismatch' ;;
    reviewed_at)
      [[ "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
        || fail 'QA reviewed_at must be UTC ISO-8601 seconds'
      ;;
  esac
  ((count += 1))
done < "$EVIDENCE_FILE"

[[ "$count" -eq 10 ]] || fail "QA evidence must have exactly 10 fields (found $count)"
echo "Ad-hoc QA record matches candidate digest and supplied identity: run=$RUN_ID sha=$SOURCE_SHA digest=$ACTUAL_DIGEST"
