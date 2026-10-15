#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-special-file-reference-fixture"
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

SPECIAL_FILE_MARKERS=(
  'FILE_SAFETY_MKFIFO_directCall'
  'FILE_SAFETY_MKFIFO_assignment'
  'FILE_SAFETY_MKFIFO_argument'
  'FILE_SAFETY_MKFIFO_labeledArgument'
  'FILE_SAFETY_MKFIFO_array'
  'FILE_SAFETY_MKFIFO_return'
  'FILE_SAFETY_MKFIFOAT_directCall'
  'FILE_SAFETY_MKFIFOAT_assignment'
  'FILE_SAFETY_MKFIFOAT_argument'
  'FILE_SAFETY_MKFIFOAT_labeledArgument'
  'FILE_SAFETY_MKFIFOAT_array'
  'FILE_SAFETY_MKFIFOAT_return'
  'FILE_SAFETY_MKNOD_directCall'
  'FILE_SAFETY_MKNOD_assignment'
  'FILE_SAFETY_MKNOD_argument'
  'FILE_SAFETY_MKNOD_labeledArgument'
  'FILE_SAFETY_MKNOD_array'
  'FILE_SAFETY_MKNOD_return'
  'FILE_SAFETY_MKNODAT_directCall'
  'FILE_SAFETY_MKNODAT_assignment'
  'FILE_SAFETY_MKNODAT_argument'
  'FILE_SAFETY_MKNODAT_labeledArgument'
  'FILE_SAFETY_MKNODAT_array'
  'FILE_SAFETY_MKNODAT_return'
)

cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_MKFIFO_directCall = mkfifo(fifoPath, 0o600)
private let FILE_SAFETY_MKFIFO_assignment = mkfifo
private let FILE_SAFETY_MKFIFO_argument = consume(mkfifo)
private let FILE_SAFETY_MKFIFO_labeledArgument = consume(callback: mkfifo)
private let FILE_SAFETY_MKFIFO_array = [mkfifo]
private let FILE_SAFETY_MKFIFO_return = { return mkfifo }
private let FILE_SAFETY_MKFIFOAT_directCall = mkfifoat(AT_FDCWD, fifoPath, 0o600)
private let FILE_SAFETY_MKFIFOAT_assignment = mkfifoat
private let FILE_SAFETY_MKFIFOAT_argument = consume(mkfifoat)
private let FILE_SAFETY_MKFIFOAT_labeledArgument = consume(callback: mkfifoat)
private let FILE_SAFETY_MKFIFOAT_array = [mkfifoat]
private let FILE_SAFETY_MKFIFOAT_return = { return mkfifoat }
private let FILE_SAFETY_MKNOD_directCall = mknod(nodePath, 0o600, 0)
private let FILE_SAFETY_MKNOD_assignment = mknod
private let FILE_SAFETY_MKNOD_argument = consume(mknod)
private let FILE_SAFETY_MKNOD_labeledArgument = consume(callback: mknod)
private let FILE_SAFETY_MKNOD_array = [mknod]
private let FILE_SAFETY_MKNOD_return = { return mknod }
private let FILE_SAFETY_MKNODAT_directCall = mknodat(AT_FDCWD, nodePath, 0o600, 0)
private let FILE_SAFETY_MKNODAT_assignment = mknodat
private let FILE_SAFETY_MKNODAT_argument = consume(mknodat)
private let FILE_SAFETY_MKNODAT_labeledArgument = consume(callback: mknodat)
private let FILE_SAFETY_MKNODAT_array = [mknodat]
private let FILE_SAFETY_MKNODAT_return = { return mknodat }
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched special-file creation mutation/reference fixture.' >&2
  exit 1
fi

failures=0
for marker in "${SPECIAL_FILE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected special-file fixture marker: $marker" >&2
    ((failures += 1))
  fi
done

mkfifo_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKFIFO_' "$OUTPUT" || true)"
mkfifoat_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKFIFOAT_' "$OUTPUT" || true)"
mknod_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKNOD_' "$OUTPUT" || true)"
mknodat_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_MKNODAT_' "$OUTPUT" || true)"
if [[ "$mkfifo_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mkfifo fixture diagnostics, found $mkfifo_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$mkfifoat_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mkfifoat fixture diagnostics, found $mkfifoat_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$mknod_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mknod fixture diagnostics, found $mknod_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$mknodat_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 mknodat fixture diagnostics, found $mknodat_diagnostic_count." >&2
  ((failures += 1))
fi

if (( failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$failures special-file creation diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyMkfifoPresentation = "mkfifo creates a named FIFO"
private let fileSafetyMkfifoatPresentation = "mkfifoat creates a named FIFO relative to a directory descriptor"
private let fileSafetyMknodPresentation = "mknod creates a special file node"
private let fileSafetyMknodatPresentation = "mknodat creates a special file node relative to a directory descriptor"
private let fileSafetyMkfifoWrapper = mkfifoWrapper
private let fileSafetyMkfifoatWrapper = mkfifoatWrapper
private let fileSafetyMknodWrapper = mknodWrapper
private let fileSafetyMknodatWrapper = mknodatWrapper
/// Documents special-file creation without invoking a filesystem mutation API.
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
allowed_status=$?
set -e

if [[ "$allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected special-file presentation/boundary fixtures.' >&2
  exit 1
fi

echo 'special-file creation mutation and first-class function-reference fixtures passed'
