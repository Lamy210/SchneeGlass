#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-clonefile-reference-fixture"
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

CLONEFILE_MARKERS=(
  'FILE_SAFETY_CLONEFILE_directCall'
  'FILE_SAFETY_CLONEFILE_assignment'
  'FILE_SAFETY_CLONEFILE_argument'
  'FILE_SAFETY_CLONEFILE_labeledArgument'
  'FILE_SAFETY_CLONEFILE_array'
  'FILE_SAFETY_CLONEFILE_return'
  'FILE_SAFETY_CLONEFILEAT_directCall'
  'FILE_SAFETY_CLONEFILEAT_assignment'
  'FILE_SAFETY_CLONEFILEAT_argument'
  'FILE_SAFETY_CLONEFILEAT_labeledArgument'
  'FILE_SAFETY_CLONEFILEAT_array'
  'FILE_SAFETY_CLONEFILEAT_return'
  'FILE_SAFETY_FCLONEFILEAT_directCall'
  'FILE_SAFETY_FCLONEFILEAT_assignment'
  'FILE_SAFETY_FCLONEFILEAT_argument'
  'FILE_SAFETY_FCLONEFILEAT_labeledArgument'
  'FILE_SAFETY_FCLONEFILEAT_array'
  'FILE_SAFETY_FCLONEFILEAT_return'
)

cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_CLONEFILE_directCall = clonefile(sourcePath, destinationPath, 0)
private let FILE_SAFETY_CLONEFILE_assignment = clonefile
private let FILE_SAFETY_CLONEFILE_argument = consume(clonefile)
private let FILE_SAFETY_CLONEFILE_labeledArgument = consume(callback: clonefile)
private let FILE_SAFETY_CLONEFILE_array = [clonefile]
private let FILE_SAFETY_CLONEFILE_return = { return clonefile }
private let FILE_SAFETY_CLONEFILEAT_directCall = clonefileat(sourceDirectory, sourcePath, destinationDirectory, destinationPath, 0)
private let FILE_SAFETY_CLONEFILEAT_assignment = clonefileat
private let FILE_SAFETY_CLONEFILEAT_argument = consume(clonefileat)
private let FILE_SAFETY_CLONEFILEAT_labeledArgument = consume(callback: clonefileat)
private let FILE_SAFETY_CLONEFILEAT_array = [clonefileat]
private let FILE_SAFETY_CLONEFILEAT_return = { return clonefileat }
private let FILE_SAFETY_FCLONEFILEAT_directCall = fclonefileat(sourceDescriptor, destinationDirectory, destinationPath, 0)
private let FILE_SAFETY_FCLONEFILEAT_assignment = fclonefileat
private let FILE_SAFETY_FCLONEFILEAT_argument = consume(fclonefileat)
private let FILE_SAFETY_FCLONEFILEAT_labeledArgument = consume(callback: fclonefileat)
private let FILE_SAFETY_FCLONEFILEAT_array = [fclonefileat]
private let FILE_SAFETY_FCLONEFILEAT_return = { return fclonefileat }
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched clonefile mutation/reference fixture.' >&2
  exit 1
fi

failures=0
for marker in "${CLONEFILE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected clonefile fixture marker: $marker" >&2
    ((failures += 1))
  fi
done

clonefile_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_CLONEFILE' "$OUTPUT" || true)"
fclonefileat_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_FCLONEFILEAT_' "$OUTPUT" || true)"
if [[ "$clonefile_diagnostic_count" -ne 12 ]]; then
  echo "Expected exactly 12 clonefile/clonefileat marker diagnostics, found $clonefile_diagnostic_count." >&2
  ((failures += 1))
fi
if [[ "$fclonefileat_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 fclonefileat marker diagnostics, found $fclonefileat_diagnostic_count." >&2
  ((failures += 1))
fi

if (( failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$failures clonefile mutation/reference diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyClonefilePresentation = "clonefile, clonefileat, and fclonefileat are APFS clone APIs"
private let fileSafetyClonefileWrapper = clonefileWrapper
private let fileSafetyClonefileatWrapper = clonefileatWrapper
private let fileSafetyFclonefileatWrapper = fclonefileatWrapper
/// Documents clonefile behavior without invoking a clone API.
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
allowed_status=$?
set -e

if [[ "$allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected clonefile presentation/boundary fixtures.' >&2
  exit 1
fi

echo 'clonefile mutation and first-class function-reference fixtures passed'
