#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-temporary-file-reference-fixture"
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

TEMPORARY_FILE_MARKERS=(
  'FILE_SAFETY_MKSTEMP_directCall'
  'FILE_SAFETY_MKSTEMP_assignment'
  'FILE_SAFETY_MKSTEMP_argument'
  'FILE_SAFETY_MKSTEMP_labeledArgument'
  'FILE_SAFETY_MKSTEMP_array'
  'FILE_SAFETY_MKSTEMP_return'
  'FILE_SAFETY_MKSTEMPS_directCall'
  'FILE_SAFETY_MKSTEMPS_assignment'
  'FILE_SAFETY_MKSTEMPS_argument'
  'FILE_SAFETY_MKSTEMPS_labeledArgument'
  'FILE_SAFETY_MKSTEMPS_array'
  'FILE_SAFETY_MKSTEMPS_return'
  'FILE_SAFETY_MKOSTEMP_directCall'
  'FILE_SAFETY_MKOSTEMP_assignment'
  'FILE_SAFETY_MKOSTEMP_argument'
  'FILE_SAFETY_MKOSTEMP_labeledArgument'
  'FILE_SAFETY_MKOSTEMP_array'
  'FILE_SAFETY_MKOSTEMP_return'
  'FILE_SAFETY_MKOSTEMPS_directCall'
  'FILE_SAFETY_MKOSTEMPS_assignment'
  'FILE_SAFETY_MKOSTEMPS_argument'
  'FILE_SAFETY_MKOSTEMPS_labeledArgument'
  'FILE_SAFETY_MKOSTEMPS_array'
  'FILE_SAFETY_MKOSTEMPS_return'
  'FILE_SAFETY_TMPFILE_directCall'
  'FILE_SAFETY_TMPFILE_assignment'
  'FILE_SAFETY_TMPFILE_argument'
  'FILE_SAFETY_TMPFILE_labeledArgument'
  'FILE_SAFETY_TMPFILE_array'
  'FILE_SAFETY_TMPFILE_return'
)

cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_MKSTEMP_directCall = mkstemp(template)
private let FILE_SAFETY_MKSTEMP_assignment = mkstemp
private let FILE_SAFETY_MKSTEMP_argument = consume(mkstemp)
private let FILE_SAFETY_MKSTEMP_labeledArgument = consume(callback: mkstemp)
private let FILE_SAFETY_MKSTEMP_array = [mkstemp]
private let FILE_SAFETY_MKSTEMP_return = { return mkstemp }
private let FILE_SAFETY_MKSTEMPS_directCall = mkstemps(template, 4)
private let FILE_SAFETY_MKSTEMPS_assignment = mkstemps
private let FILE_SAFETY_MKSTEMPS_argument = consume(mkstemps)
private let FILE_SAFETY_MKSTEMPS_labeledArgument = consume(callback: mkstemps)
private let FILE_SAFETY_MKSTEMPS_array = [mkstemps]
private let FILE_SAFETY_MKSTEMPS_return = { return mkstemps }
private let FILE_SAFETY_MKOSTEMP_directCall = mkostemp(template, 0)
private let FILE_SAFETY_MKOSTEMP_assignment = mkostemp
private let FILE_SAFETY_MKOSTEMP_argument = consume(mkostemp)
private let FILE_SAFETY_MKOSTEMP_labeledArgument = consume(callback: mkostemp)
private let FILE_SAFETY_MKOSTEMP_array = [mkostemp]
private let FILE_SAFETY_MKOSTEMP_return = { return mkostemp }
private let FILE_SAFETY_MKOSTEMPS_directCall = mkostemps(template, 4, 0)
private let FILE_SAFETY_MKOSTEMPS_assignment = mkostemps
private let FILE_SAFETY_MKOSTEMPS_argument = consume(mkostemps)
private let FILE_SAFETY_MKOSTEMPS_labeledArgument = consume(callback: mkostemps)
private let FILE_SAFETY_MKOSTEMPS_array = [mkostemps]
private let FILE_SAFETY_MKOSTEMPS_return = { return mkostemps }
private let FILE_SAFETY_TMPFILE_directCall = tmpfile()
private let FILE_SAFETY_TMPFILE_assignment = tmpfile
private let FILE_SAFETY_TMPFILE_argument = consume(tmpfile)
private let FILE_SAFETY_TMPFILE_labeledArgument = consume(callback: tmpfile)
private let FILE_SAFETY_TMPFILE_array = [tmpfile]
private let FILE_SAFETY_TMPFILE_return = { return tmpfile }
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched temporary-file creation/reference fixture.' >&2
  exit 1
fi

failures=0
for marker in "${TEMPORARY_FILE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected temporary-file fixture marker: $marker" >&2
    ((failures += 1))
  fi
done

mkstemp_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKSTEMP_' "$OUTPUT" || true)"
mkstemps_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKSTEMPS_' "$OUTPUT" || true)"
mkostemp_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKOSTEMP_' "$OUTPUT" || true)"
mkostemps_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKOSTEMPS_' "$OUTPUT" || true)"
tmpfile_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_TMPFILE_' "$OUTPUT" || true)"
if [[ "$mkstemp_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mkstemp fixture diagnostics, found $mkstemp_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$mkstemps_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mkstemps fixture diagnostics, found $mkstemps_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$mkostemp_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mkostemp fixture diagnostics, found $mkostemp_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$mkostemps_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mkostemps fixture diagnostics, found $mkostemps_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$tmpfile_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 tmpfile fixture diagnostics, found $tmpfile_diagnostic_count." >&2
  ((failures += 1))
fi

if (( failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$failures temporary-file creation diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyMkstempPresentation = "mkstemp creates a unique temporary file"
private let fileSafetyMkstempsPresentation = "mkstemps creates a unique temporary file with a suffix"
private let fileSafetyMkostempPresentation = "mkostemp creates a unique temporary file with open flags"
private let fileSafetyMkostempsPresentation = "mkostemps creates a unique temporary file with a suffix and open flags"
private let fileSafetyTmpfilePresentation = "tmpfile creates and unlinks a temporary file"
private let fileSafetyMkstempWrapper = mkstempWrapper
private let fileSafetyMkstempsWrapper = mkstempsWrapper
private let fileSafetyMkostempWrapper = mkostempWrapper
private let fileSafetyMkostempsWrapper = mkostempsWrapper
private let fileSafetyTmpfileWrapper = tmpfileWrapper
/// Documents temporary-file creation without invoking a filesystem mutation API.
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
allowed_status=$?
set -e

if [[ "$allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected temporary-file presentation/boundary fixtures.' >&2
  exit 1
fi

echo 'temporary-file creation mutation and first-class function-reference fixtures passed'
