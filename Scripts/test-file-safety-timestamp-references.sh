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

# Batch the rejected-reference fixtures into one guard scan. A unique marker
# for each API/context pair is mandatory: an unrelated rejection cannot mask a
# missed detection. Accepted prose and quoted text are still tested separately.
FAILURES=0
EXPECTED_MARKERS=()
cp "$LOCK_BACKUP" "$LOCK_SOURCE"

for timestamp_case in utime utimes futimes lutimes futimens utimensat; do
  for reference_context in directCall assignment argument labeledArgument array return; do
    marker="FILE_SAFETY_TIMESTAMP_${timestamp_case}_${reference_context}"
    case "$reference_context" in
      directCall)
        source_line="private let $marker = $timestamp_case(timestampFixture)"
        ;;
      assignment)
        source_line="private let $marker = $timestamp_case"
        ;;
      argument)
        source_line="private let $marker = consume($timestamp_case)"
        ;;
      labeledArgument)
        source_line="private let $marker = consume(callback: $timestamp_case)"
        ;;
      array)
        source_line="private let $marker = [$timestamp_case]"
        ;;
      return)
        source_line="private let $marker = { return $timestamp_case }"
        ;;
    esac
    printf '%s\n' "$source_line" >> "$LOCK_SOURCE"
    EXPECTED_MARKERS+=("$marker")
  done
done

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
batched_status=$?
set -e

if [[ "$batched_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed batched POSIX timestamp references.' >&2
  exit 1
fi

if ! "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT"; then
  echo 'File Safety Guard failed without source-level timestamp diagnostics.' >&2
  exit 1
fi

for marker in "${EXPECTED_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not report timestamp fixture: $marker" >&2
    ((FAILURES += 1))
  fi
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
