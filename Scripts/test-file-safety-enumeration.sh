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
  'an unreviewed positioned POSIX write' \
  'private let fileSafetyPositionedRawWrite = pwrite(0, nil, 0, 0)' \
  'pwrite('

expect_forbidden_source_line \
  'an unreviewed Foundation URL write' \
  'private let fileSafetyFoundationURLWrite = try? Data().write(to: URL(fileURLWithPath: "/tmp/schneeglass-file-safety-fixture"))' \
  '.write(to:'

expect_forbidden_source_line \
  'an unreviewed extended-attribute write' \
  'private let fileSafetyExtendedAttributeWrite = fsetxattr(0, "proof", nil, 0, 0, 0)' \
  'fsetxattr('

expect_forbidden_source_line \
  'an unreviewed extended-attribute removal' \
  'private let fileSafetyExtendedAttributeRemoval = fremovexattr(0, "proof", 0)' \
  'fremovexattr('

expect_forbidden_source_line \
  'an unreviewed path-based extended-attribute write' \
  'private let fileSafetyPathExtendedAttributeWrite = setxattr("/tmp/schneeglass-file-safety-fixture", "proof", nil, 0, 0, 0)' \
  'setxattr('

expect_forbidden_source_line \
  'an unreviewed path-based extended-attribute removal' \
  'private let fileSafetyPathExtendedAttributeRemoval = removexattr("/tmp/schneeglass-file-safety-fixture", "proof", 0)' \
  'removexattr('

expect_forbidden_source_line \
  'an unreviewed FileManager copy' \
  'private let fileSafetyCopyItem = try? FileManager.default.copyItem(atPath: "/tmp/schneeglass-copy-source", toPath: "/tmp/schneeglass-copy-destination")' \
  '.copyItem('

expect_forbidden_source_line \
  'an unreviewed FileManager remove method reference' \
  'private let fileSafetyRemoveItemReference: (URL) throws -> Void = FileManager.default.removeItem' \
  '.removeItem'

expect_forbidden_source_line \
  'an unreviewed FileManager move method reference' \
  'private let fileSafetyMoveItemReference: (URL, URL) throws -> Void = FileManager.default.moveItem' \
  '.moveItem'

expect_forbidden_source_line \
  'an unreviewed FileManager copy method reference' \
  'private let fileSafetyCopyItemReference: (URL, URL) throws -> Void = FileManager.default.copyItem' \
  '.copyItem'

expect_forbidden_source_line \
  'an unreviewed FileManager replace method reference' \
  'private let fileSafetyReplaceItemReference = FileManager.default.replaceItemAt' \
  '.replaceItemAt'

expect_forbidden_source_line \
  'an unreviewed FileManager create-directory method reference' \
  'private let fileSafetyCreateDirectoryReference: (String, Bool, [FileAttributeKey: Any]?) throws -> Void = FileManager.default.createDirectory' \
  '.createDirectory'

expect_forbidden_source_line \
  'an unreviewed FileManager create-file method reference' \
  'private let fileSafetyCreateFileReference: (String, Data?, [FileAttributeKey: Any]?) -> Bool = FileManager.default.createFile' \
  '.createFile'

expect_forbidden_source_line \
  'an unreviewed FileManager symbolic-link creation' \
  'private let fileSafetyCreateSymbolicLink = try? FileManager.default.createSymbolicLink(at: URL(fileURLWithPath: "/tmp/schneeglass-file-safety-link"), withDestinationURL: URL(fileURLWithPath: "/tmp/schneeglass-file-safety-target"))' \
  '.createSymbolicLink'

expect_forbidden_source_line \
  'an unreviewed FileManager hard-link creation' \
  'private let fileSafetyLinkItem = try? FileManager.default.linkItem(at: URL(fileURLWithPath: "/tmp/schneeglass-file-safety-link-source"), to: URL(fileURLWithPath: "/tmp/schneeglass-file-safety-hard-link"))' \
  '.linkItem'

expect_forbidden_source_line \
  'an unreviewed POSIX hard-link creation' \
  'private let fileSafetyLink = link("/tmp/schneeglass-file-safety-link-source", "/tmp/schneeglass-file-safety-hard-link")' \
  'link('

expect_forbidden_source_line \
  'an unreviewed descriptor-relative POSIX hard-link creation' \
  'private let fileSafetyLinkAt = linkat(AT_FDCWD, "/tmp/schneeglass-file-safety-link-source", AT_FDCWD, "/tmp/schneeglass-file-safety-hard-link", 0)' \
  'linkat('

expect_forbidden_source_line \
  'an unreviewed POSIX directory creation' \
  'private let fileSafetyMkdir = mkdir("/tmp/schneeglass-file-safety-directory", mode_t(0o700))' \
  'mkdir('

expect_forbidden_source_line \
  'an unreviewed POSIX directory removal' \
  'private let fileSafetyRmdir = rmdir("/tmp/schneeglass-file-safety-directory")' \
  'rmdir('

expect_forbidden_source_line \
  'an unreviewed POSIX rename' \
  'private let fileSafetyRename = rename("/tmp/schneeglass-file-safety-source", "/tmp/schneeglass-file-safety-destination")' \
  'rename('

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

echo 'File Safety Guard enumeration, App-scope, allowlist-boundary, destructive-truncation, xattr, copy-item, FileManager-reference, FileManager-creation, POSIX-directory-creation/removal, POSIX-rename, and raw-write fixtures passed'
