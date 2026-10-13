#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-timestamp-reference-fixture"
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

expect_allowed_source_line() {
  local label="$1"
  local source_line="$2"

  cp "$LOCK_BACKUP" "$LOCK_SOURCE"
  printf '%s\n' "$source_line" >> "$LOCK_SOURCE"

  set +e
  bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
  local status=$?
  set -e

  if [[ "$status" -ne 0 ]]; then
    cat "$OUTPUT" >&2
    echo "File Safety Guard unexpectedly rejected: $label" >&2
    return 1
  fi
}

FAILURES=0
for timestamp_case in utime utimes futimes lutimes futimens utimensat; do
  for reference_context in directCall assignment argument labeledArgument array return; do
    case "$reference_context" in
      directCall)
        source_line="private let fileSafetyTimestampReference = $timestamp_case(timestampFixture)"
        ;;
      assignment)
        source_line="private let fileSafetyTimestampReference = $timestamp_case"
        ;;
      argument)
        source_line="private let fileSafetyTimestampReference = consume($timestamp_case)"
        ;;
      labeledArgument)
        source_line="private let fileSafetyTimestampReference = consume(callback: $timestamp_case)"
        ;;
      array)
        source_line="private let fileSafetyTimestampReference = [$timestamp_case]"
        ;;
      return)
        source_line="private let fileSafetyTimestampReference = { return $timestamp_case }"
        ;;
    esac

    if ! expect_forbidden_reference \
      "an unreviewed POSIX $timestamp_case $reference_context timestamp mutation reference" \
      "$source_line" \
      "$timestamp_case"; then
      FAILURES=$((FAILURES + 1))
    fi
  done
done

if ! expect_allowed_source_line \
  'quoted timestamp API presentation text' \
  'private let fileSafetyTimestampPresentation = "utime, utimes, futimes, lutimes, futimens, utimensat are POSIX timestamp APIs"'; then
  FAILURES=$((FAILURES + 1))
fi

if ! expect_allowed_source_line \
  'timestamp API prose comment' \
  '/// Reviews timestamp mutations such as utime, utimes, futimes, lutimes, futimens, and utimensat without invoking them.'; then
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX timestamp mutation/reference fixture(s) failed." >&2
  exit 1
fi

echo 'POSIX timestamp mutation/reference fixtures passed'
