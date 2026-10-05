#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
OUTPUT="$FIXTURE/output.log"
LOCK_SOURCE="$ROOT/Packages/SchneeGlassKit/Sources/SchneeGlassPersistenceAdapter/ApplicationProcessLock.swift"
LOCK_BACKUP="$FIXTURE/ApplicationProcessLock.swift.backup"
APP_SOURCE="$ROOT/App/CompositionRoot.swift"
APP_BACKUP="$FIXTURE/CompositionRoot.swift.backup"

REAL_GREP="$(command -v grep)"

cleanup() {
  if [[ -f "$LOCK_BACKUP" ]]; then
    cp "$LOCK_BACKUP" "$LOCK_SOURCE"
  fi
  if [[ -f "$APP_BACKUP" ]]; then
    cp "$APP_BACKUP" "$APP_SOURCE"
  fi
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
echo 'fixture: grep enumeration unavailable' >&2
exit 42
SHIM
chmod +x "$FIXTURE/bin/grep"

set +e
PATH="$FIXTURE/bin:$PATH" bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'File Safety Guard unexpectedly passed when mutation enumeration failed.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'File safety verification failed: unable to enumerate filesystem mutation pattern' \
  "$OUTPUT"

cp "$LOCK_SOURCE" "$LOCK_BACKUP"
cp "$APP_SOURCE" "$APP_BACKUP"

expect_forbidden_source_line() {
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

  "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT"
  "$REAL_GREP" -Fq "$expected_fragment" "$OUTPUT"
}

expect_forbidden_source_line \
  'a forbidden mutation hidden by an allowlisted token' \
  'private let fileSafetySmuggledMutation = unlink("/tmp/schneeglass-file-safety-fixture")  // O_CREAT' \
  'unlink('

expect_forbidden_source_line \
  'a destructive O_TRUNC open' \
  'private let fileSafetyTruncatingOpen = open("/tmp/schneeglass-file-safety-fixture", O_WRONLY | O_TRUNC)' \
  'O_TRUNC'

expect_forbidden_source_line \
  'an unreviewed raw POSIX write' \
  'private let fileSafetyRawWrite = Darwin.write(0, nil, 0)' \
  'Darwin.write('

expect_forbidden_source_line \
  'an unreviewed unqualified POSIX write' \
  'private let fileSafetyUnqualifiedRawWrite = write(0, nil, 0)' \
  'write('

expect_forbidden_source_line \
  'an unreviewed extended-attribute write' \
  'private let fileSafetyExtendedAttributeWrite = fsetxattr(0, "proof", nil, 0, 0, 0)' \
  'fsetxattr('

expect_forbidden_source_line \
  'an unreviewed extended-attribute removal' \
  'private let fileSafetyExtendedAttributeRemoval = fremovexattr(0, "proof", 0)' \
  'fremovexattr('

cp "$APP_BACKUP" "$APP_SOURCE"
printf '%s\n' \
  'private let fileSafetyAppRemove = try? FileManager.default.removeItem(atPath: "/tmp/schneeglass-file-safety-app-fixture")' \
  >> "$APP_SOURCE"

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
APP_STATUS=$?
set -e

if [[ "$APP_STATUS" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed an App-layer filesystem mutation.' >&2
  exit 1
fi

"$REAL_GREP" -Fq 'CompositionRoot.swift' "$OUTPUT"
"$REAL_GREP" -Fq '.removeItem(' "$OUTPUT"
cp "$APP_BACKUP" "$APP_SOURCE"

FAILURES=0
for destructive_case in creat truncate ftruncate; do
  case "$destructive_case" in
    creat)
      source_line='private let fileSafetyCreat = creat("/tmp/schneeglass-file-safety-fixture", mode_t(0o600))'
      expected_fragment='creat('
      ;;
    truncate)
      source_line='private let fileSafetyTruncate = truncate("/tmp/schneeglass-file-safety-fixture", 0)'
      expected_fragment='truncate('
      ;;
    ftruncate)
      source_line='private let fileSafetyFtruncate = ftruncate(0, 0)'
      expected_fragment='ftruncate('
      ;;
  esac

  if ! expect_forbidden_source_line \
    "a destructive $destructive_case mutation" \
    "$source_line" \
    "$expected_fragment"; then
    FAILURES=$((FAILURES + 1))
  fi
done

cp "$LOCK_BACKUP" "$LOCK_SOURCE"
cp "$APP_BACKUP" "$APP_SOURCE"
rm -f "$LOCK_BACKUP" "$APP_BACKUP"

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES destructive truncation primitive fixture(s) were not rejected." >&2
  exit 1
fi

echo 'File Safety Guard enumeration, App-scope, allowlist-boundary, destructive-truncation, xattr, and raw-write fixtures passed'
