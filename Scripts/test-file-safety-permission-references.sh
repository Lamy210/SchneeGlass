#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-permission-reference-fixture"
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

# Batch the forbidden first-class function references without skipping any
# API/context pair. A distinct marker per case is required so a rejected
# unrelated source line cannot hide a missing detector.
FAILURES=0
EXPECTED_MARKERS=()
cp "$LOCK_BACKUP" "$LOCK_SOURCE"

for permission_reference_case in chmod fchmod fchmodat; do
  for reference_context in assignment argument labeledArgument array return; do
    marker="FILE_SAFETY_PERMISSION_${permission_reference_case}_${reference_context}"
    case "$reference_context" in
      assignment)
        source_line="private let $marker = $permission_reference_case"
        ;;
      argument)
        source_line="private let $marker = consume($permission_reference_case)"
        ;;
      labeledArgument)
        source_line="private let $marker = consume(callback: $permission_reference_case)"
        ;;
      array)
        source_line="private let $marker = [$permission_reference_case]"
        ;;
      return)
        source_line="private let $marker = { return $permission_reference_case }"
        ;;
    esac
    printf '%s\n' "$source_line" >> "$LOCK_SOURCE"
    EXPECTED_MARKERS+=("$marker")
  done
done

if [[ "${#EXPECTED_MARKERS[@]}" -ne 15 ]]; then
  echo 'Expected exactly 15 POSIX permission reference fixtures.' >&2
  exit 1
fi

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
batched_status=$?
set -e

if [[ "$batched_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed batched POSIX permission references.' >&2
  exit 1
fi

if ! "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT"; then
  echo 'File Safety Guard failed without source-level permission diagnostics.' >&2
  exit 1
fi

for marker in "${EXPECTED_MARKERS[@]}"; do
  matches=$("$REAL_GREP" -Fc "$marker" "$OUTPUT" || true)
  if [[ "$matches" -ne 1 ]]; then
    echo "Expected exactly one File Safety diagnostic for: $marker (found $matches)" >&2
    ((FAILURES += 1))
  fi
done

if ! expect_allowed_source_line \
  'quoted permission API presentation text' \
  'private let fileSafetyPermissionPresentation = "chmod, fchmod, fchmodat are POSIX permission APIs"'; then
  FAILURES=$((FAILURES + 1))
fi

if ! expect_allowed_source_line \
  'permission API prose comment' \
  '/// Reviews permission mutations such as chmod, fchmod, and fchmodat without invoking them.'; then
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX permission function-reference fixture(s) failed." >&2
  exit 1
fi

echo 'POSIX permission function-reference fixtures passed'
