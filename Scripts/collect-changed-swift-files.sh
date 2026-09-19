#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Swift-format changed-file enumeration failed: $*" >&2
  exit 1
}

if [[ "$#" -ne 2 ]]; then
  fail "usage: $0 <base-sha> <output-file>"
fi

BASE_SHA="$1"
OUTPUT_FILE="$2"
OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"

[[ -n "$BASE_SHA" ]] || fail "base SHA must not be empty"
[[ -d "$OUTPUT_DIR" ]] || fail "output directory does not exist: $OUTPUT_DIR"

rm -f "$OUTPUT_FILE"
TEMP_OUTPUT="$(mktemp "$OUTPUT_FILE.tmp.XXXXXX")" \
  || fail "unable to create temporary changed-file output"

cleanup() {
  rm -f "$TEMP_OUTPUT"
}
trap cleanup EXIT

set +e
git diff \
  --name-only \
  --diff-filter=ACMR \
  -z \
  "$BASE_SHA...HEAD" \
  -- '*.swift' \
  > "$TEMP_OUTPUT"
DIFF_STATUS=$?
set -e

if [[ "$DIFF_STATUS" -ne 0 ]]; then
  fail "git diff could not enumerate changed Swift files (status $DIFF_STATUS)"
fi

mv "$TEMP_OUTPUT" "$OUTPUT_FILE" \
  || fail "unable to commit changed-file enumeration output"
trap - EXIT
