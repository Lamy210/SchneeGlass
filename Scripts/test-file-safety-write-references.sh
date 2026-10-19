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

COMMENTED_DARWIN_WRITE_MARKER='FILE_SAFETY_DARWIN_WRITE_commentedAssignment'

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_DARWIN_WRITE_commentedAssignment = Darwin.write // reviewed as a callback
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
commented_darwin_write_status=$?
set -e

if [[ "$commented_darwin_write_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed Darwin.write assignment with a trailing comment.' >&2
  exit 1
fi

if ! "$REAL_GREP" -Fq "$COMMENTED_DARWIN_WRITE_MARKER" "$OUTPUT"; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard did not diagnose commented Darwin.write assignment.' >&2
  exit 1
fi

commented_darwin_write_count="$("$REAL_GREP" -Fc "$COMMENTED_DARWIN_WRITE_MARKER" "$OUTPUT" || true)"
if [[ "$commented_darwin_write_count" -ne 1 ]]; then
  cat "$OUTPUT" >&2
  echo "Expected exactly 1 commented Darwin.write assignment diagnostic, found $commented_darwin_write_count." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyCommentedOtherDarwinWrite = SomeDarwin.write // unrelated namespace
private let fileSafetyCommentedWriteWrapper = Darwin.writeWrapper // unrelated symbol
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
commented_darwin_write_boundary_status=$?
set -e

if [[ "$commented_darwin_write_boundary_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard rejected non-Darwin write symbols with trailing comments.' >&2
  exit 1
fi

# Preserve raw-write authority classification when Swift comments follow a qualified callback assignment.
COMMENTED_QUALIFIED_MARKERS=(
  'FILE_SAFETY_COMMENTED_DARWIN_PWRITE'
  'FILE_SAFETY_COMMENTED_DARWIN_WRITEV'
  'FILE_SAFETY_COMMENTED_DARWIN_PWRITEV'
)

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_COMMENTED_DARWIN_PWRITE = Darwin.pwrite // positioned callback
private let FILE_SAFETY_COMMENTED_DARWIN_WRITEV = Darwin.writev    // vectored callback
private let FILE_SAFETY_COMMENTED_DARWIN_PWRITEV = Darwin.pwritev// positioned vectored callback
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
commented_qualified_status=$?
set -e

if [[ "$commented_qualified_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed Darwin.pwrite/writev/pwritev assignments with trailing comments.' >&2
  exit 1
fi

commented_qualified_failures=0
for marker in "${COMMENTED_QUALIFIED_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose commented qualified raw-write reference: $marker" >&2
    ((commented_qualified_failures += 1))
  fi
done

commented_qualified_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_COMMENTED_DARWIN_' "$OUTPUT" || true)"
if [[ "$commented_qualified_count" -ne 3 ]]; then
  echo "Expected exactly 3 commented qualified raw-write diagnostics, found $commented_qualified_count." >&2
  ((commented_qualified_failures += 1))
fi

if (( commented_qualified_failures != 0 )); then
  cat "$OUTPUT" >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyOtherDarwinPwriteCommented = SomeDarwin.pwrite // unrelated namespace
private let fileSafetyOtherDarwinWritevCommented = SomeDarwin.writev // unrelated namespace
private let fileSafetyOtherDarwinPwritevCommented = SomeDarwin.pwritev // unrelated namespace
private let fileSafetyDarwinPwriteWrapperCommented = Darwin.pwriteWrapper // unrelated symbol
private let fileSafetyDarwinWritevWrapperCommented = Darwin.writevWrapper // unrelated symbol
private let fileSafetyDarwinPwritevWrapperCommented = Darwin.pwritevWrapper // unrelated symbol
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
commented_qualified_boundary_status=$?
set -e

if [[ "$commented_qualified_boundary_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard rejected unrelated qualified raw-write symbols with trailing comments.' >&2
  exit 1
fi

# A trailing Swift line comment must not conceal a bare POSIX write callback.
COMMENTED_BARE_WRITE_MARKERS=(
  'FILE_SAFETY_COMMENTED_BARE_WRITE'
  'FILE_SAFETY_COMMENTED_BARE_PWRITE'
  'FILE_SAFETY_COMMENTED_BARE_WRITEV'
  'FILE_SAFETY_COMMENTED_BARE_PWRITEV'
)

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_COMMENTED_BARE_WRITE = write // raw write callback
private let FILE_SAFETY_COMMENTED_BARE_PWRITE = pwrite    // positioned callback
private let FILE_SAFETY_COMMENTED_BARE_WRITEV = writev// vectored callback
private let FILE_SAFETY_COMMENTED_BARE_PWRITEV = pwritev // positioned vectored callback
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
commented_bare_write_status=$?
set -e

if [[ "$commented_bare_write_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed commented bare write/pwrite/writev/pwritev callbacks.' >&2
  exit 1
fi

commented_bare_write_failures=0
for marker in "${COMMENTED_BARE_WRITE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not detect expected commented bare raw-write reference: $marker" >&2
    ((commented_bare_write_failures += 1))
  fi
done

commented_bare_write_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_COMMENTED_BARE_' "$OUTPUT" || true)"
if [[ "$commented_bare_write_count" -ne 4 ]]; then
  echo "Expected exactly 4 commented bare raw-write diagnostics, found $commented_bare_write_count." >&2
  ((commented_bare_write_failures += 1))
fi

if (( commented_bare_write_failures != 0 )); then
  cat "$OUTPUT" >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyBareWriteWrapperWithComment = writeWrapper // not a raw-write callback
private let fileSafetyBarePwriteWrapperWithComment = pwriteWrapper // not a raw-write callback
private let fileSafetyBareWritevWrapperWithComment = writevWrapper // not a raw-write callback
private let fileSafetyBarePwritevWrapperWithComment = pwritevWrapper // not a raw-write callback
private let fileSafetyMemberWriteWithComment = OtherAPI.write // unrelated member
private let fileSafetyMemberPwriteWithComment = OtherAPI.pwrite // unrelated member
private let fileSafetyMemberWritevWithComment = OtherAPI.writev // unrelated member
private let fileSafetyMemberPwritevWithComment = OtherAPI.pwritev // unrelated member
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
commented_bare_write_boundary_status=$?
set -e

if [[ "$commented_bare_write_boundary_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard rejected unrelated bare-write names or members with comments.' >&2
  exit 1
fi

# A single-line Swift block comment must not hide raw-write callback authority.
BLOCK_COMMENT_RAW_WRITE_MARKERS=(
  'FILE_SAFETY_BLOCK_COMMENT_BARE_WRITE'
  'FILE_SAFETY_BLOCK_COMMENT_BARE_PWRITE'
  'FILE_SAFETY_BLOCK_COMMENT_BARE_WRITEV'
  'FILE_SAFETY_BLOCK_COMMENT_BARE_PWRITEV'
  'FILE_SAFETY_BLOCK_COMMENT_DARWIN_WRITE'
  'FILE_SAFETY_BLOCK_COMMENT_DARWIN_PWRITE'
  'FILE_SAFETY_BLOCK_COMMENT_DARWIN_WRITEV'
  'FILE_SAFETY_BLOCK_COMMENT_DARWIN_PWRITEV'
)

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_BLOCK_COMMENT_BARE_WRITE = write /* callback */
private let FILE_SAFETY_BLOCK_COMMENT_BARE_PWRITE = pwrite/* positioned callback */
private let FILE_SAFETY_BLOCK_COMMENT_BARE_WRITEV = writev /* vectored * callback */
private let FILE_SAFETY_BLOCK_COMMENT_BARE_PWRITEV = pwritev /* positioned callback */ // retained
private let FILE_SAFETY_BLOCK_COMMENT_DARWIN_WRITE = Darwin.write /* callback */
private let FILE_SAFETY_BLOCK_COMMENT_DARWIN_PWRITE = Darwin.pwrite/* positioned callback */
private let FILE_SAFETY_BLOCK_COMMENT_DARWIN_WRITEV = Darwin.writev /* vectored * callback */
private let FILE_SAFETY_BLOCK_COMMENT_DARWIN_PWRITEV = Darwin.pwritev /* positioned callback */ // retained
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
block_comment_status=$?
set -e

if [[ "$block_comment_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed block-commented raw-write callback references.' >&2
  exit 1
fi

block_comment_failures=0
for marker in "${BLOCK_COMMENT_RAW_WRITE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose block-commented raw-write reference: $marker" >&2
    ((block_comment_failures += 1))
  fi
done

block_comment_diagnostics="$("$REAL_GREP" -Fc 'FILE_SAFETY_BLOCK_COMMENT_' "$OUTPUT" || true)"
if [[ "$block_comment_diagnostics" -ne 8 ]]; then
  echo "Expected exactly 8 block-commented raw-write diagnostics, found $block_comment_diagnostics." >&2
  ((block_comment_failures += 1))
fi

if (( block_comment_failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$block_comment_failures block-comment raw-write diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetyBlockCommentOtherWrite = OtherAPI.write /* unrelated member */
private let fileSafetyBlockCommentOtherPwrite = OtherAPI.pwrite /* unrelated member */
private let fileSafetyBlockCommentOtherWritev = OtherAPI.writev /* unrelated member */
private let fileSafetyBlockCommentOtherPwritev = OtherAPI.pwritev /* unrelated member */
private let fileSafetyBlockCommentSomeDarwinWrite = SomeDarwin.write /* unrelated namespace */
private let fileSafetyBlockCommentSomeDarwinPwrite = SomeDarwin.pwrite /* unrelated namespace */
private let fileSafetyBlockCommentSomeDarwinWritev = SomeDarwin.writev /* unrelated namespace */
private let fileSafetyBlockCommentSomeDarwinPwritev = SomeDarwin.pwritev /* unrelated namespace */
private let fileSafetyBlockCommentWriteWrapper = writeWrapper /* unrelated identifier */
private let fileSafetyBlockCommentDarwinWrapper = Darwin.writeWrapper /* unrelated identifier */
private let fileSafetyBlockCommentPresentation = "write /* documentation */"
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
block_comment_boundary_status=$?
set -e

if [[ "$block_comment_boundary_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard rejected unrelated block-commented identifier/member fixtures.' >&2
  exit 1
fi

# A Swift statement terminator must not hide raw-write function-reference authority.
SEMICOLON_RAW_WRITE_MARKERS=(
  'FILE_SAFETY_SEMICOLON_BARE_WRITE'
  'FILE_SAFETY_SEMICOLON_BARE_PWRITE'
  'FILE_SAFETY_SEMICOLON_BARE_WRITEV'
  'FILE_SAFETY_SEMICOLON_BARE_PWRITEV'
  'FILE_SAFETY_SEMICOLON_DARWIN_WRITE'
  'FILE_SAFETY_SEMICOLON_DARWIN_PWRITE'
  'FILE_SAFETY_SEMICOLON_DARWIN_WRITEV'
  'FILE_SAFETY_SEMICOLON_DARWIN_PWRITEV'
)

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let FILE_SAFETY_SEMICOLON_BARE_WRITE = write;
private let FILE_SAFETY_SEMICOLON_BARE_PWRITE = pwrite ; // callback
private let FILE_SAFETY_SEMICOLON_BARE_WRITEV = writev; private let fileSafetySafeAfterBareWritev = 1
private let FILE_SAFETY_SEMICOLON_BARE_PWRITEV = pwritev /* callback */ ; // trailing comment
private let FILE_SAFETY_SEMICOLON_DARWIN_WRITE = Darwin.write;
private let FILE_SAFETY_SEMICOLON_DARWIN_PWRITE = Darwin.pwrite ; // callback
private let FILE_SAFETY_SEMICOLON_DARWIN_WRITEV = Darwin.writev; private let fileSafetySafeAfterDarwinWritev = 1
private let FILE_SAFETY_SEMICOLON_DARWIN_PWRITEV = Darwin.pwritev /* callback */ ; // trailing comment
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
semicolon_raw_write_status=$?
set -e

if [[ "$semicolon_raw_write_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed semicolon-terminated raw-write function references.' >&2
  exit 1
fi

semicolon_raw_write_failures=0
for marker in "${SEMICOLON_RAW_WRITE_MARKERS[@]}"; do
  if ! "$REAL_GREP" -Fq "$marker" "$OUTPUT"; then
    echo "File Safety Guard did not diagnose semicolon-terminated raw-write reference: $marker" >&2
    ((semicolon_raw_write_failures += 1))
  fi
done

semicolon_raw_write_count="$("$REAL_GREP" -Fc 'FILE_SAFETY_SEMICOLON_' "$OUTPUT" || true)"
if [[ "$semicolon_raw_write_count" -ne 8 ]]; then
  echo "Expected exactly 8 semicolon raw-write reference diagnostics, found $semicolon_raw_write_count." >&2
  ((semicolon_raw_write_failures += 1))
fi

if (( semicolon_raw_write_failures != 0 )); then
  cat "$OUTPUT" >&2
  echo "$semicolon_raw_write_failures semicolon diagnostic assertion(s) failed." >&2
  exit 1
fi

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cat >> "$LOCK_SOURCE" <<'EOF'
private let fileSafetySemicolonOtherWrite = OtherAPI.write;
private let fileSafetySemicolonOtherPwrite = OtherAPI.pwrite;
private let fileSafetySemicolonOtherWritev = OtherAPI.writev;
private let fileSafetySemicolonOtherPwritev = OtherAPI.pwritev;
private let fileSafetySemicolonSomeDarwinWrite = SomeDarwin.write;
private let fileSafetySemicolonSomeDarwinPwrite = SomeDarwin.pwrite;
private let fileSafetySemicolonSomeDarwinWritev = SomeDarwin.writev;
private let fileSafetySemicolonSomeDarwinPwritev = SomeDarwin.pwritev;
private let fileSafetySemicolonWriteWrapper = writeWrapper;
private let fileSafetySemicolonDarwinWrapper = Darwin.writeWrapper;
private let fileSafetySemicolonPresentation = "write; is a statement terminator";
EOF

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
semicolon_raw_write_boundary_status=$?
set -e

if [[ "$semicolon_raw_write_boundary_status" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  echo 'File Safety Guard rejected unrelated semicolon-terminated identifier/member fixtures.' >&2
  exit 1
fi

echo 'POSIX raw-write function-reference fixtures passed'
cp "$LOCK_BACKUP" "$LOCK_SOURCE"
bash Scripts/test-file-safety-temporary-file-references.sh
