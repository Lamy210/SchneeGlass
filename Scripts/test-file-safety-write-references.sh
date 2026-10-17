#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-write-reference-fixture"
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
for write_reference_case in Darwin.write write pwrite Darwin.pwrite writev Darwin.writev; do
  for reference_context in assignment argument labeledArgument array return; do
    case "$reference_context" in
      assignment)
        source_line="private let fileSafetyWriteReference = $write_reference_case"
        ;;
      argument)
        source_line="private let fileSafetyWriteReference = consume($write_reference_case)"
        ;;
      labeledArgument)
        source_line="private let fileSafetyWriteReference = consume(callback: $write_reference_case)"
        ;;
      array)
        source_line="private let fileSafetyWriteReference = [$write_reference_case]"
        ;;
      return)
        source_line="private let fileSafetyWriteReference = { return $write_reference_case }"
        ;;
    esac

    if ! expect_forbidden_reference \
      "an unreviewed POSIX $write_reference_case $reference_context raw-write function reference" \
      "$source_line" \
      "$write_reference_case"; then
      FAILURES=$((FAILURES + 1))
    fi
  done
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX raw-write function-reference fixture(s) were not rejected." >&2
  exit 1
fi

QUALIFIED_RAW_WRITE_MARKERS=(
  'FILE_SAFETY_DARWIN_PWRITE_directCall'
  'FILE_SAFETY_DARWIN_PWRITE_assignment'
  'FILE_SAFETY_DARWIN_PWRITE_argument'
  'FILE_SAFETY_DARWIN_PWRITE_labeledArgument'
  'FILE_SAFETY_DARWIN_PWRITE_array'
  'FILE_SAFETY_DARWIN_PWRITE_return'
  'FILE_SAFETY_DARWIN_WRITEV_directCall'
  'FILE_SAFETY_DARWIN_WRITEV_assignment'
  'FILE_SAFETY_DARWIN_WRITEV_argument'
  'FILE_SAFETY_DARWIN_WRITEV_labeledArgument'
  'FILE_SAFETY_DARWIN_WRITEV_array'
  'FILE_SAFETY_DARWIN_WRITEV_return'
)

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_DARWIN_PWRITE_directCall = Darwin.pwrite(0, nil, 0, 0)
private let FILE_SAFETY_DARWIN_PWRITE_assignment = Darwin.pwrite
private let FILE_SAFETY_DARWIN_PWRITE_argument = consume(Darwin.pwrite)
private let FILE_SAFETY_DARWIN_PWRITE_labeledArgument = consume(callback: Darwin.pwrite)
private let FILE_SAFETY_DARWIN_PWRITE_array = [Darwin.pwrite]
private let FILE_SAFETY_DARWIN_PWRITE_return = { return Darwin.pwrite }
private let FILE_SAFETY_DARWIN_WRITEV_directCall = Darwin.writev(0, nil, 0)
private let FILE_SAFETY_DARWIN_WRITEV_assignment = Darwin.writev
private let FILE_SAFETY_DARWIN_WRITEV_argument = consume(Darwin.writev)
private let FILE_SAFETY_DARWIN_WRITEV_labeledArgument = consume(callback: Darwin.writev)
private let FILE_SAFETY_DARWIN_WRITEV_array = [Darwin.writev]
private let FILE_SAFETY_DARWIN_WRITEV_return = { return Darwin.writev }
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
qualified_raw_write_status=$?
set -e

if [[ "$qualified_raw_write_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched Darwin.pwrite/Darwin.writev fixture.' >&2
  exit 1
fi

qualified_raw_write_failures=0
for marker in "${QUALIFIED_RAW_WRITE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected qualified raw-write fixture marker: $marker" >&2
    ((qualified_raw_write_failures += 1))
  fi
done

darwin_pwrite_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_DARWIN_PWRITE_' "$OUTPUT" || true)"
darwin_writev_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_DARWIN_WRITEV_' "$OUTPUT" || true)"
if [[ "$darwin_pwrite_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 Darwin.pwrite fixture diagnostics, found $darwin_pwrite_diagnostic_count." >&2
  ((qualified_raw_write_failures += 1))
fi
if [[ "$darwin_writev_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 Darwin.writev fixture diagnostics, found $darwin_writev_diagnostic_count." >&2
  ((qualified_raw_write_failures += 1))
fi

if (( qualified_raw_write_failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$qualified_raw_write_failures qualified raw-write diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyDarwinPwritePresentation = "Darwin.pwrite names a positioned write"
private let fileSafetyDarwinPwriteWrapper = Darwin.pwriteWrapper
private let fileSafetyOtherDarwinPwriteCall = SomeDarwin.pwrite(0, nil, 0, 0)
private let fileSafetyDarwinWritevPresentation = "Darwin.writev names a vectored write"
private let fileSafetyDarwinWritevWrapper = Darwin.writevWrapper
private let fileSafetyOtherDarwinWritevCall = SomeDarwin.writev(0, nil, 0)
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
qualified_raw_write_allowed_status=$?
set -e

if [[ "$qualified_raw_write_allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected Darwin.pwrite/Darwin.writev boundary fixtures.' >&2
  exit 1
fi

PWRITEV_MARKERS=(
  'FILE_SAFETY_PWRITEV_directCall'
  'FILE_SAFETY_PWRITEV_assignment'
  'FILE_SAFETY_PWRITEV_argument'
  'FILE_SAFETY_PWRITEV_labeledArgument'
  'FILE_SAFETY_PWRITEV_array'
  'FILE_SAFETY_PWRITEV_return'
  'FILE_SAFETY_DARWIN_PWRITEV_directCall'
  'FILE_SAFETY_DARWIN_PWRITEV_assignment'
  'FILE_SAFETY_DARWIN_PWRITEV_argument'
  'FILE_SAFETY_DARWIN_PWRITEV_labeledArgument'
  'FILE_SAFETY_DARWIN_PWRITEV_array'
  'FILE_SAFETY_DARWIN_PWRITEV_return'
)

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_PWRITEV_directCall = pwritev(0, nil, 0, 0)
private let FILE_SAFETY_PWRITEV_assignment = pwritev
private let FILE_SAFETY_PWRITEV_argument = consume(pwritev)
private let FILE_SAFETY_PWRITEV_labeledArgument = consume(callback: pwritev)
private let FILE_SAFETY_PWRITEV_array = [pwritev]
private let FILE_SAFETY_PWRITEV_return = { return pwritev }
private let FILE_SAFETY_DARWIN_PWRITEV_directCall = Darwin.pwritev(0, nil, 0, 0)
private let FILE_SAFETY_DARWIN_PWRITEV_assignment = Darwin.pwritev
private let FILE_SAFETY_DARWIN_PWRITEV_argument = consume(Darwin.pwritev)
private let FILE_SAFETY_DARWIN_PWRITEV_labeledArgument = consume(callback: Darwin.pwritev)
private let FILE_SAFETY_DARWIN_PWRITEV_array = [Darwin.pwritev]
private let FILE_SAFETY_DARWIN_PWRITEV_return = { return Darwin.pwritev }
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
pwritev_status=$?
set -e

if [[ "$pwritev_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the batched pwritev raw-write/reference fixture.' >&2
  exit 1
fi

pwritev_failures=0
for marker in "${PWRITEV_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose expected pwritev fixture marker: $marker" >&2
    ((pwritev_failures += 1))
  fi
done

pwritev_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_PWRITEV_' "$OUTPUT" || true)"
darwin_pwritev_diagnostic_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_DARWIN_PWRITEV_' "$OUTPUT" || true)"
if [[ "$pwritev_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 unqualified pwritev fixture diagnostics, found $pwritev_diagnostic_count." >&2
  ((pwritev_failures += 1))
fi
if [[ "$darwin_pwritev_diagnostic_count" -ne 6 ]]; then
  echo "Expected exactly 6 Darwin.pwritev fixture diagnostics, found $darwin_pwritev_diagnostic_count." >&2
  ((pwritev_failures += 1))
fi

if (( pwritev_failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$pwritev_failures pwritev raw-write diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyPwritevPresentation = "pwritev performs a positioned vectored write"
private let fileSafetyPwritevWrapper = pwritevWrapper
private let fileSafetyDarwinPwritevPresentation = "Darwin.pwritev names a positioned vectored write"
private let fileSafetyDarwinPwritevWrapper = Darwin.pwritevWrapper
private let fileSafetyOtherDarwinPwritevCall = SomeDarwin.pwritev(0, nil, 0, 0)
/// Documents positioned vectored writes without invoking a filesystem mutation API.
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
pwritev_allowed_status=$?
set -e

if [[ "$pwritev_allowed_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected pwritev presentation/boundary fixtures.' >&2
  exit 1
fi

DARWIN_WRITE_DIRECT_MARKER='FILE_SAFETY_DARWIN_WRITE_directCall'

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_DARWIN_WRITE_directCall = Darwin.write(0, nil, 0)
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
darwin_write_direct_status=$?
set -e

if [[ "$darwin_write_direct_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed the Darwin.write direct-call fixture.' >&2
  exit 1
fi

if ! "$REAL_GREP" -Fq "$DARWIN_WRITE_DIRECT_MARKER" "$OUTPUT"; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard did not diagnose the Darwin.write direct-call fixture.' >&2
  exit 1
fi

darwin_write_direct_count="$("$REAL_GREP" -Fc "$DARWIN_WRITE_DIRECT_MARKER" "$OUTPUT" || true)"
if [[ "$darwin_write_direct_count" -ne 1 ]]; then
  cat "$OUTPUT" >&2
  echo "Expected exactly 1 Darwin.write direct-call diagnostic, found $darwin_write_direct_count." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyDarwinWritePresentation = "Darwin.write names a raw write"
private let fileSafetyDarwinWriteWrapper = Darwin.writeWrapper
private let fileSafetyOtherDarwinWriteCall = SomeDarwin.write(0, nil, 0)
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
darwin_write_boundary_status=$?
set -e

if [[ "$darwin_write_boundary_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard unexpectedly rejected Darwin.write boundary fixtures.' >&2
  exit 1
fi

echo 'POSIX raw-write function-reference fixtures passed'
cp "$LOCK_BACKUP" "$LOCK_SOURCE"
bash Scripts/test-file-safety-temporary-file-references.sh
