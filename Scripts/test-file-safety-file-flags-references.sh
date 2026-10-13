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

restore_source() {
  cp "$LOCK_BACKUP" "$LOCK_SOURCE"
}

FORBIDDEN_MARKERS=()
restore_source
for file_flags_case in chflags fchflags lchflags; do
  for reference_context in directCall assignment argument labeledArgument array return; do
    marker="FILE_SAFETY_FILE_FLAGS_${file_flags_case}_${reference_context}"
    FORBIDDEN_MARKERS+=("$marker")

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

    printf '%s // %s\n' "$source_line" "$marker" >> "$LOCK_SOURCE"
  done
done

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
FORBIDDEN_STATUS=$?
set -e

if [[ "$FORBIDDEN_STATUS" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched POSIX file flag mutation/reference fixture.' >&2
  exit 1
fi

FAILURES=0
for marker in "${FORBIDDEN_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected file flag fixture marker: $marker" >&2
    FAILURES=$((FAILURES + 1))
  fi
done

DIAGNOSTIC_COUNT="$("$REAL_GREP" -Fc 'FILE_SAFETY_FILE_FLAGS_' "$OUTPUT" || true)"
if [[ "$DIAGNOSTIC_COUNT" -ne 18 ]]; then
  echo "Expected exactly 18 file flag fixture diagnostics, found $DIAGNOSTIC_COUNT." >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo "$FAILURES POSIX file flag mutation/reference diagnostic assertion(s) failed." >&2
  exit 1
fi

restore_source
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyFileFlagsPresentation = "chflags, fchflags, lchflags are POSIX file flag APIs"
/// Reviews file flag mutations such as chflags, fchflags, and lchflags without invoking them.
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
ALLOWED_STATUS=$?
set -e

if [[ "$ALLOWED_STATUS" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected file flag presentation/prose fixtures.' >&2
  exit 1
fi

echo 'POSIX file flag mutation/reference fixtures passed'
