#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-fcopyfile-reference-fixture"
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

case_names=(
  'assignment'
  'argument'
  'labeled argument'
  'array'
  'return'
)
case_lines=(
  'private let fileSafetyFcopyfileReference = fcopyfile'
  'private let fileSafetyFcopyfileArgumentReference = consume(fcopyfile)'
  'private let fileSafetyFcopyfileLabeledArgumentReference = consume(callback: fcopyfile)'
  'private let fileSafetyFcopyfileArrayReference = [fcopyfile]'
  'private let fileSafetyFcopyfileReturnReference = { return fcopyfile }'
)

failures=0
for index in "${!case_names[@]}"; do
  case_name="${case_names[$index]}"
  case_line="${case_lines[$index]}"

  cp "$LOCK_BACKUP" "$LOCK_SOURCE"
  printf '%s\n' "$case_line" >> "$LOCK_SOURCE"

  set +e
  bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    echo "File Safety Guard unexpectedly allowed: an unreviewed fcopyfile $case_name function reference" >&2
    ((failures += 1))
    continue
  fi

  if ! "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT" \
     || ! "$REAL_GREP" -Fq 'fcopyfile' "$OUTPUT"; then
    echo "File Safety Guard rejected the fcopyfile $case_name fixture without the expected diagnostic" >&2
    ((failures += 1))
  fi
done

if (( failures != 0 )); then
  echo "$failures fcopyfile first-class function-reference fixture(s) were not rejected." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
COPYFILE_MARKERS=(
  'FILE_SAFETY_COPYFILE_directCall'
  'FILE_SAFETY_COPYFILE_assignment'
  'FILE_SAFETY_COPYFILE_argument'
  'FILE_SAFETY_COPYFILE_labeledArgument'
  'FILE_SAFETY_COPYFILE_array'
  'FILE_SAFETY_COPYFILE_return'
)
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_COPYFILE_directCall = copyfile(copyfileSource, copyfileDestination, nil, 0)
private let FILE_SAFETY_COPYFILE_assignment = copyfile
private let FILE_SAFETY_COPYFILE_argument = consume(copyfile)
private let FILE_SAFETY_COPYFILE_labeledArgument = consume(callback: copyfile)
private let FILE_SAFETY_COPYFILE_array = [copyfile]
private let FILE_SAFETY_COPYFILE_return = { return copyfile }
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
copyfile_status=$?
set -e

if [[ "$copyfile_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched copyfile mutation/reference fixture.' >&2
  exit 1
fi

copyfile_failures=0
for marker in "${COPYFILE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected copyfile fixture marker: $marker" >&2
    ((copyfile_failures += 1))
  fi
done

copyfile_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_COPYFILE_' "$OUTPUT" || true)"
if [[ "$copyfile_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 copyfile fixture diagnostics, found $copyfile_diagnostic_count." >&2
  ((copyfile_failures += 1))
fi

if (( copyfile_failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$copyfile_failures copyfile mutation/reference diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyCopyfilePresentation = "copyfile is a POSIX copy API"
private let fileSafetyCopyfileWrapper = copyfileWrapper
/// Documents copyfile behavior without invoking it.
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
allowed_status=$?
set -e

if [[ "$allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected copyfile presentation/boundary fixtures.' >&2
  exit 1
fi

echo 'copyfile/fcopyfile mutation and first-class function-reference fixtures passed'
