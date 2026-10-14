#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-temp-creation-reference-fixture"
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

TEMP_CREATION_APIS=(
  mkstemp
  mkstemps
  mkostemp
  mkostemps
  mkdtemp
  mkdtempat_np
  mkstempsat_np
  mkostempsat_np
)

for api in "${TEMP_CREATION_APIS[@]}"; do
  case "$api" in
    mkstemp)
      direct_call='mkstemp(&template)'
      ;;
    mkstemps)
      direct_call='mkstemps(&template, 4)'
      ;;
    mkostemp)
      direct_call='mkostemp(&template, 0)'
      ;;
    mkostemps)
      direct_call='mkostemps(&template, 4, 0)'
      ;;
    mkdtemp)
      direct_call='mkdtemp(&template)'
      ;;
    mkdtempat_np)
      direct_call='mkdtempat_np(AT_FDCWD, &template)'
      ;;
    mkstempsat_np)
      direct_call='mkstempsat_np(AT_FDCWD, &template, 4)'
      ;;
    mkostempsat_np)
      direct_call='mkostempsat_np(AT_FDCWD, &template, 4, 0)'
      ;;
  esac

  cat >> "$LOCK_SOURCE" <<EOF
private let FILE_SAFETY_TEMP_${api}_directCall = $direct_call
private let FILE_SAFETY_TEMP_${api}_assignment = $api
private let FILE_SAFETY_TEMP_${api}_argument = consume($api)
private let FILE_SAFETY_TEMP_${api}_labeledArgument = consume(callback: $api)
private let FILE_SAFETY_TEMP_${api}_array = [$api]
private let FILE_SAFETY_TEMP_${api}_return = { return $api }
EOF
done

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched temporary creation mutation/reference fixture.' >&2
  exit 1
fi

failures=0
for api in "${TEMP_CREATION_APIS[@]}"; do
  for context in directCall assignment argument labeledArgument array return; do
    marker="FILE_SAFETY_TEMP_${api}_${context}"
    if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
      echo "File Safety Guard did not diagnose expected temporary creation fixture marker: $marker" >&2
      ((failures += 1))
    fi
  done

  diagnostic_count="$("$REAL_GREP" -Fc "FILE_SAFETY_TEMP_${api}_" "$OUTPUT" || true)"
  if [[ "$diagnostic_count" -ne 6 ]]; then
    echo "Expected exactly 6 $api fixture diagnostics, found $diagnostic_count." >&2
    ((failures += 1))
  fi
done

if (( failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$failures temporary creation diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
for api in "${TEMP_CREATION_APIS[@]}"; do
  cat >> "$LOCK_SOURCE" <<EOF
private let fileSafetyTempPresentation_${api} = "$api temporary creation API"
private let fileSafetyTempWrapper_${api} = ${api}Wrapper
EOF
done

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
allowed_status=$?
set -e

if [[ "$allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected temporary creation presentation/boundary fixtures.' >&2
  exit 1
fi

echo 'temporary creation mutation and first-class function-reference fixtures passed'
