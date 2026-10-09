#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-destructive-reference-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"
OUTPUT="$FIXTURE/output.log"
LOCK_SOURCE="$ROOT/Packages/SchneeGlassKit/Sources/SchneeGlassPersistenceAdapter/ApplicationProcessLock.swift"
LOCK_BACKUP="$FIXTURE/ApplicationProcessLock.swift.backup"
REAL_GREP="$(command -v grep)"

cleanup() {
  if [[ -f "$LOCK_BACKUP" ]]; then
    cp "$LOCK_BACKUP" "$LOCK_SOURCE"
  fi
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

cp "$LOCK_SOURCE" "$LOCK_BACKUP"

expect_forbidden_reference() {
  local label="$1"
  local source_line="$2"
  local expected_fragment="$3"

  cp "$LOCK_BACKUP" "$LOCK_SOURCE"
  printf '%s\n' "$source_line" >> "$LOCK_SOURCE"

  set +e
  bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "File Safety Guard unexpectedly allowed: $label" >&2
    return 1
  fi

  if ! "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT" \
     || ! "$REAL_GREP" -Fq "$expected_fragment" "$OUTPUT"; then
    echo "File Safety Guard rejected $label without the expected diagnostic" >&2
    return 1
  fi
}

FAILURES=0
for destructive_reference_case in creat truncate ftruncate; do
  for reference_context in assignment argument array return; do
    case "$reference_context" in
      assignment)
        source_line="private let fileSafetyDestructiveReference = $destructive_reference_case"
        ;;
      argument)
        source_line="private let fileSafetyDestructiveReference = consume($destructive_reference_case)"
        ;;
      array)
        source_line="private let fileSafetyDestructiveReference = [$destructive_reference_case]"
        ;;
      return)
        source_line="private let fileSafetyDestructiveReference = { return $destructive_reference_case }"
        ;;
    esac

    if ! expect_forbidden_reference \
      "an unreviewed POSIX $destructive_reference_case $reference_context destructive function reference" \
      "$source_line" \
      "$destructive_reference_case"; then
      FAILURES=$((FAILURES + 1))
    fi
  done
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX destructive function-reference fixture(s) were not rejected." >&2
  exit 1
fi

echo 'POSIX destructive function-reference fixtures passed'
