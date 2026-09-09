#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release build history validation failed: $*" >&2
  exit 1
}

CURRENT_EVIDENCE="${1:-}"
HISTORY_DIR="${2:-}"

[[ -n "$CURRENT_EVIDENCE" ]] || fail "current evidence path is required"
[[ -f "$CURRENT_EVIDENCE" ]] || fail "current evidence is missing: $CURRENT_EVIDENCE"
[[ -n "$HISTORY_DIR" ]] || fail "history directory is required"
[[ -d "$HISTORY_DIR" ]] || fail "history directory is missing: $HISTORY_DIR"

read_single_value() {
  local file="$1"
  local key="$2"
  local count
  count="$(grep -c "^${key}=" "$file" || true)"
  [[ "$count" == "1" ]] || fail "$file must contain exactly one $key"
  sed -n "s/^${key}=//p" "$file"
}

CURRENT_SCHEMA="$(read_single_value "$CURRENT_EVIDENCE" schema_version)"
CURRENT_BUILD="$(read_single_value "$CURRENT_EVIDENCE" bundle_build)"
[[ "$CURRENT_SCHEMA" == "1" ]] || fail "unsupported current evidence schema: $CURRENT_SCHEMA"
[[ "$CURRENT_BUILD" =~ ^[1-9][0-9]*$ ]] || fail "current bundle_build is invalid: $CURRENT_BUILD"

MAX_PUBLISHED_BUILD=0
PUBLISHED_COUNT=0

while IFS= read -r evidence; do
  [[ -n "$evidence" ]] || continue
  PUBLISHED_COUNT=$((PUBLISHED_COUNT + 1))

  schema="$(read_single_value "$evidence" schema_version)"
  build="$(read_single_value "$evidence" bundle_build)"
  [[ "$schema" == "1" ]] || fail "unsupported historical evidence schema in $evidence: $schema"
  [[ "$build" =~ ^[1-9][0-9]*$ ]] || fail "historical bundle_build is invalid in $evidence: $build"

  if (( build > MAX_PUBLISHED_BUILD )); then
    MAX_PUBLISHED_BUILD="$build"
  fi
done < <(find "$HISTORY_DIR" -type f -name RELEASE_EVIDENCE.txt -print | sort)

if (( PUBLISHED_COUNT == 0 )); then
  echo "Release build history OK: first public release, current build=$CURRENT_BUILD"
  exit 0
fi

(( CURRENT_BUILD > MAX_PUBLISHED_BUILD )) \
  || fail "current build $CURRENT_BUILD must be greater than published maximum $MAX_PUBLISHED_BUILD"

echo "Release build history OK: current=$CURRENT_BUILD published_max=$MAX_PUBLISHED_BUILD releases=$PUBLISHED_COUNT"
