#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-ownership-reference-fixture"
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

# Retain each negative fixture but scan the repository only once. A distinct
# identifier per API and reference context prevents unrelated guard failures
# from hiding a missing detector.
FAILURES=0
EXPECTED_MARKERS=()
cp "$LOCK_BACKUP" "$LOCK_SOURCE"
for ownership_reference_case in chown fchown lchown fchownat; do
  for reference_context in assignment argument labeledArgument array return; do
    marker="FILE_SAFETY_OWNERSHIP_${ownership_reference_case}_${reference_context}"
    case "$reference_context" in
      assignment)
        source_line="private let $marker = $ownership_reference_case"
        ;;
      argument)
        source_line="private let $marker = consume($ownership_reference_case)"
        ;;
      labeledArgument)
        source_line="private let $marker = consume(callback: $ownership_reference_case)"
        ;;
      array)
        source_line="private let $marker = [$ownership_reference_case]"
        ;;
      return)
        source_line="private let $marker = { return $ownership_reference_case }"
        ;;
    esac
    printf '%s\n' "$source_line" >> "$LOCK_SOURCE"
    EXPECTED_MARKERS+=("$marker")
  done
done

if [[ "${#EXPECTED_MARKERS[@]}" -ne 20 ]]; then
  echo 'Expected exactly 20 POSIX ownership reference fixtures.' >&2
  exit 1
fi

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
batched_status=$?
set -e

if [[ "$batched_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed batched POSIX ownership references.' >&2
  exit 1
fi

if ! "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT"; then
  echo 'File Safety Guard failed without source-level ownership diagnostics.' >&2
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
  'quoted ownership API presentation text' \
  'private let fileSafetyOwnershipPresentation = "chown, fchown, lchown, fchownat are POSIX ownership APIs"'; then
  FAILURES=$((FAILURES + 1))
fi

if ! expect_allowed_source_line \
  'ownership API prose comment' \
  '/// Reviews ownership mutations such as chown, fchown, lchown, and fchownat without invoking them.'; then
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX ownership function-reference fixture(s) failed." >&2
  exit 1
fi

echo 'POSIX ownership function-reference fixtures passed'
