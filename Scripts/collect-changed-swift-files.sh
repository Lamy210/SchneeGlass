#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "usage: $0 <base-sha> <output-file>" >&2
  exit 1
fi

BASE_SHA="$1"
OUTPUT_FILE="$2"

: > "$OUTPUT_FILE"

while IFS= read -r -d '' file; do
  printf '%s\0' "$file" >> "$OUTPUT_FILE"
done < <(
  git diff \
    --name-only \
    --diff-filter=ACMR \
    -z \
    "$BASE_SHA...HEAD" \
    -- '*.swift'
)
