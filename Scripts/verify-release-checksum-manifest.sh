#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release checksum manifest verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 2 ]] || fail "usage: $0 <candidate-directory> <archive-name>"

CANDIDATE_DIR="$1"
ARCHIVE_NAME="$2"

[[ -n "$CANDIDATE_DIR" ]] || fail "candidate directory must not be empty"
[[ -n "$ARCHIVE_NAME" && "$ARCHIVE_NAME" != */* ]] \
  || fail "archive name must be a non-empty leaf filename"

MANIFEST="$CANDIDATE_DIR/SHA256SUMS"
ARCHIVE="$CANDIDATE_DIR/$ARCHIVE_NAME"

[[ -f "$ARCHIVE" ]] || fail "candidate archive is missing: $ARCHIVE_NAME"
[[ -f "$MANIFEST" ]] || fail "SHA256SUMS is missing"

if ! LINE_COUNT="$(awk 'END { print NR }' "$MANIFEST")"; then
  fail "unable to enumerate SHA256SUMS entries"
fi

[[ "$LINE_COUNT" == "1" ]] \
  || fail "SHA256SUMS must contain exactly one entry; found $LINE_COUNT"

IFS= read -r MANIFEST_LINE < "$MANIFEST" \
  || fail "unable to read SHA256SUMS entry"

[[ "${#MANIFEST_LINE}" -ge 66 ]] \
  || fail "SHA256SUMS entry is malformed"

DIGEST="${MANIFEST_LINE:0:64}"
SEPARATOR="${MANIFEST_LINE:64:2}"
ENTRY_NAME="${MANIFEST_LINE:66}"

[[ "$DIGEST" =~ ^[0-9a-fA-F]{64}$ ]] \
  || fail "SHA256SUMS digest must be exactly 64 hexadecimal characters"
[[ "$SEPARATOR" == "  " ]] \
  || fail "SHA256SUMS must use exactly two spaces between digest and filename"
[[ "$ENTRY_NAME" == "$ARCHIVE_NAME" ]] \
  || fail "SHA256SUMS archive entry mismatch: expected $ARCHIVE_NAME, found $ENTRY_NAME"

(
  cd "$CANDIDATE_DIR"
  shasum -a 256 -c SHA256SUMS
)

echo "Release checksum manifest verified for $ARCHIVE_NAME"
