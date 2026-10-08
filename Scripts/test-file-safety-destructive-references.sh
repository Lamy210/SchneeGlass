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

  "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT"
  "$REAL_GREP" -Fq "$expected_fragment" "$OUTPUT"
}

FAILURES=0
for destructive_reference_case in creat truncate ftruncate; do
  case "$destructive_reference_case" in
    creat)
      source_line='private let fileSafetyCreatReference = creat'
      expected_fragment='creat'
      ;;
    truncate)
      source_line='private let fileSafetyTruncateReference = truncate'
      expected_fragment='truncate'
      ;;
    ftruncate)
      source_line='private let fileSafetyFtruncateReference = ftruncate'
      expected_fragment='ftruncate'
      ;;
  esac

  if ! expect_forbidden_reference \
    "an unreviewed POSIX $destructive_reference_case destructive function reference" \
    "$source_line" \
    "$expected_fragment"; then
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX destructive function-reference fixture(s) were not rejected." >&2
  exit 1
fi

echo 'POSIX destructive function-reference fixtures passed'
