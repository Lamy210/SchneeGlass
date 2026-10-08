#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-xattr-reference-fixture"
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
for xattr_reference_case in setxattr removexattr fsetxattr fremovexattr; do
  case "$xattr_reference_case" in
    setxattr)
      source_line='private let fileSafetySetXattrReference = setxattr'
      expected_fragment='setxattr'
      ;;
    removexattr)
      source_line='private let fileSafetyRemoveXattrReference = removexattr'
      expected_fragment='removexattr'
      ;;
    fsetxattr)
      source_line='private let fileSafetyFsetXattrReference = fsetxattr'
      expected_fragment='fsetxattr'
      ;;
    fremovexattr)
      source_line='private let fileSafetyFremoveXattrReference = fremovexattr'
      expected_fragment='fremovexattr'
      ;;
  esac

  if ! expect_forbidden_reference \
    "an unreviewed POSIX $xattr_reference_case extended-attribute function reference" \
    "$source_line" \
    "$expected_fragment"; then
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX xattr function-reference fixture(s) were not rejected." >&2
  exit 1
fi

echo 'POSIX xattr function-reference fixtures passed'
