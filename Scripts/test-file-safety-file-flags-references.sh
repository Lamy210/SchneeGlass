#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-file-flags-reference-fixture"
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
for file_flags_case in chflags fchflags lchflags; do
  for reference_context in directCall assignment argument labeledArgument array return; do
    case "$reference_context" in
      directCall)
        source_line="private let fileSafetyFileFlagsReference = $file_flags_case(fileFlagsFixture)"
        ;;
      assignment)
        source_line="private let fileSafetyFileFlagsReference = $file_flags_case"
        ;;
      argument)
        source_line="private let fileSafetyFileFlagsReference = consume($file_flags_case)"
        ;;
      labeledArgument)
        source_line="private let fileSafetyFileFlagsReference = consume(callback: $file_flags_case)"
        ;;
      array)
        source_line="private let fileSafetyFileFlagsReference = [$file_flags_case]"
        ;;
      return)
        source_line="private let fileSafetyFileFlagsReference = { return $file_flags_case }"
        ;;
    esac

    if ! expect_forbidden_reference \
      "an unreviewed POSIX $file_flags_case $reference_context file flag mutation reference" \
      "$source_line" \
      "$file_flags_case"; then
      FAILURES=$((FAILURES + 1))
    fi
  done
done

if ! expect_allowed_source_line \
  'quoted file flag API presentation text' \
  'private let fileSafetyFileFlagsPresentation = "chflags, fchflags, lchflags are POSIX file flag APIs"'; then
  FAILURES=$((FAILURES + 1))
fi

if ! expect_allowed_source_line \
  'file flag API prose comment' \
  '/// Reviews file flag mutations such as chflags, fchflags, and lchflags without invoking them.'; then
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX file flag mutation/reference fixture(s) failed." >&2
  exit 1
fi

echo 'POSIX file flag mutation/reference fixtures passed'
