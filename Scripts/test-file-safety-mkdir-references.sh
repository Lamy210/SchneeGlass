#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-mkdir-reference-fixture"
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
for mkdir_reference_case in mkdir mkdirat; do
  for reference_context in assignment argument labeledArgument array return; do
    case "$reference_context" in
      assignment)
        source_line="private let fileSafetyMkdirReference = $mkdir_reference_case"
        ;;
      argument)
        source_line="private let fileSafetyMkdirReference = consume($mkdir_reference_case)"
        ;;
      labeledArgument)
        source_line="private let fileSafetyMkdirReference = consume(callback: $mkdir_reference_case)"
        ;;
      array)
        source_line="private let fileSafetyMkdirReference = [$mkdir_reference_case]"
        ;;
      return)
        source_line="private let fileSafetyMkdirReference = { return $mkdir_reference_case }"
        ;;
    esac

    if ! expect_forbidden_reference \
      "an unreviewed POSIX $mkdir_reference_case $reference_context directory-creation function reference" \
      "$source_line" \
      "$mkdir_reference_case"; then
      FAILURES=$((FAILURES + 1))
    fi
  done
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX directory-creation function-reference fixture(s) failed." >&2
  exit 1
fi

echo 'POSIX directory-creation function-reference fixtures passed'

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
MKDTEMP_MARKERS=(
  'FILE_SAFETY_MKDTEMP_directCall'
  'FILE_SAFETY_MKDTEMP_assignment'
  'FILE_SAFETY_MKDTEMP_argument'
  'FILE_SAFETY_MKDTEMP_labeledArgument'
  'FILE_SAFETY_MKDTEMP_array'
  'FILE_SAFETY_MKDTEMP_return'
)

cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_MKDTEMP_directCall = mkdtemp(template)
private let FILE_SAFETY_MKDTEMP_assignment = mkdtemp
private let FILE_SAFETY_MKDTEMP_argument = consume(mkdtemp)
private let FILE_SAFETY_MKDTEMP_labeledArgument = consume(callback: mkdtemp)
private let FILE_SAFETY_MKDTEMP_array = [mkdtemp]
private let FILE_SAFETY_MKDTEMP_return = { return mkdtemp }
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
mkdtemp_status=$?
set -e

if [[ "$mkdtemp_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched mkdtemp directory-creation/reference fixture.' >&2
  exit 1
fi

mkdtemp_failures=0
for marker in "${MKDTEMP_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected mkdtemp fixture marker: $marker" >&2
    ((mkdtemp_failures += 1))
  fi
done

mkdtemp_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKDTEMP_' "$OUTPUT" || true)"
if [[ "$mkdtemp_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mkdtemp fixture diagnostics, found $mkdtemp_diagnostic_count." >&2
  ((mkdtemp_failures += 1))
fi

if (( mkdtemp_failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$mkdtemp_failures mkdtemp diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyMkdtempPresentation = "mkdtemp creates a unique temporary directory"
private let fileSafetyMkdtempWrapper = mkdtempWrapper
/// Documents mkdtemp policy without invoking a filesystem mutation API.
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
mkdtemp_allowed_status=$?
set -e

if [[ "$mkdtemp_allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected mkdtemp presentation/boundary fixtures.' >&2
  exit 1
fi

echo 'mkdtemp directory-creation and first-class function-reference fixtures passed'

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
bash Scripts/test-file-safety-special-file-references.sh
