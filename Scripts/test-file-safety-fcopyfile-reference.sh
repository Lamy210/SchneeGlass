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
  'array'
  'return'
)
case_lines=(
  'private let fileSafetyFcopyfileReference = fcopyfile'
  'private let fileSafetyFcopyfileArgumentReference = consume(fcopyfile)'
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

echo 'fcopyfile first-class function-reference fixtures passed'
