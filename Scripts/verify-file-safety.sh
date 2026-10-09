#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/Packages/SchneeGlassKit/Sources"
APP="$ROOT/App"

fail() {
  echo "File safety verification failed: $*" >&2
  exit 1
}

TMP_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
MATCHES_FILE="$(mktemp "$TMP_BASE/schneeglass-file-safety-matches.XXXXXX")"
SORTED_MATCHES_FILE="$(mktemp "$TMP_BASE/schneeglass-file-safety-sorted.XXXXXX")"
SCAN_FILE="$(mktemp "$TMP_BASE/schneeglass-file-safety-scan.XXXXXX")"
cleanup() {
  rm -f "$MATCHES_FILE" "$SORTED_MATCHES_FILE" "$SCAN_FILE"
}
trap cleanup EXIT

scan_pattern() {
  local mutation="$1"
  local pattern="$2"
  local status
  local match

  : > "$SCAN_FILE"
  set +e
  grep -RInE "$pattern" "$SRC" "$APP" --include='*.swift' > "$SCAN_FILE"
  status=$?
  set -e

  case "$status" in
    0)
      while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        printf '%s\t%s\n' "$mutation" "$match" >> "$MATCHES_FILE"
      done < "$SCAN_FILE"
      ;;
    1)
      ;;
    *)
      fail "unable to enumerate filesystem mutation pattern: $mutation (grep status $status)"
      ;;
  esac
}

: > "$MATCHES_FILE"
scan_pattern 'FileManager removeItem' '\.removeItem([^[:alnum:]_]|$)'
scan_pattern 'FileManager moveItem' '\.moveItem([^[:alnum:]_]|$)'
scan_pattern 'FileManager copyItem' '\.copyItem([^[:alnum:]_]|$)'
scan_pattern 'FileManager setAttributes' '\.setAttributes([^[:alnum:]_]|$)'
scan_pattern 'FileManager createDirectory' '\.createDirectory([^[:alnum:]_]|$)'
scan_pattern 'FileManager createFile' '\.createFile([^[:alnum:]_]|$)'
scan_pattern 'FileManager createSymbolicLink' '\.createSymbolicLink([^[:alnum:]_]|$)'
scan_pattern 'FileManager linkItem' '\.linkItem([^[:alnum:]_]|$)'
scan_pattern 'FileManager replaceItemAt' '\.replaceItemAt([^[:alnum:]_]|$)'
scan_pattern 'link' '(^|[^[:alnum:]_])link\(|=[[:space:]]*link[[:space:]]*$'
scan_pattern 'linkat' '(^|[^[:alnum:]_])linkat\(|=[[:space:]]*linkat[[:space:]]*$'
scan_pattern 'symlink' '(^|[^[:alnum:]_])symlink\(|=[[:space:]]*symlink[[:space:]]*$'
scan_pattern 'symlinkat' '(^|[^[:alnum:]_])symlinkat\(|=[[:space:]]*symlinkat[[:space:]]*$'
scan_pattern 'unlink' '(^|[^[:alnum:]_])unlink([^[:alnum:]_]|$)'
scan_pattern 'unlinkat' '(^|[^[:alnum:]_])unlinkat([^[:alnum:]_]|$)'
scan_pattern 'rmdir' '(^|[^[:alnum:]_])rmdir([^[:alnum:]_]|$)'
scan_pattern 'rename' '(^|[^[:alnum:]_])rename\(|=[[:space:]]*rename[[:space:]]*$'
scan_pattern 'renameat' '(^|[^[:alnum:]_])renameat\(|=[[:space:]]*renameat[[:space:]]*$'
scan_pattern 'renameatx_np' '(^|[^[:alnum:]_])renameatx_np\(|=[[:space:]]*renameatx_np[[:space:]]*$'
scan_pattern 'mkdir' '(^|[^[:alnum:]_])mkdir\(|=[[:space:]]*mkdir[[:space:]]*$'
scan_pattern 'mkdirat' '(^|[^[:alnum:]_])mkdirat\(|=[[:space:]]*mkdirat[[:space:]]*$'
scan_pattern 'chmod' '(^|[^[:alnum:]_])chmod\(|=[[:space:]]*chmod[[:space:]]*$'
scan_pattern 'fchmod' '(^|[^[:alnum:]_])fchmod\(|=[[:space:]]*fchmod[[:space:]]*$'
scan_pattern 'fchmodat' '(^|[^[:alnum:]_])fchmodat\(|=[[:space:]]*fchmodat[[:space:]]*$'
scan_pattern 'chown' '(^|[^[:alnum:]_])chown\(|=[[:space:]]*chown[[:space:]]*$'
scan_pattern 'fchown' '(^|[^[:alnum:]_])fchown\(|=[[:space:]]*fchown[[:space:]]*$'
scan_pattern 'lchown' '(^|[^[:alnum:]_])lchown\(|=[[:space:]]*lchown[[:space:]]*$'
scan_pattern 'fchownat' '(^|[^[:alnum:]_])fchownat\(|=[[:space:]]*fchownat[[:space:]]*$'
scan_pattern 'fcopyfile' '(^|[^[:alnum:]_])fcopyfile\(|=[[:space:]]*fcopyfile[[:space:]]*$|(\(|\[|,)[[:space:]]*fcopyfile[[:space:]]*(\)|\]|,)|return[[:space:]]+fcopyfile([^[:alnum:]_]|$)'
scan_pattern 'creat' '(^|[^[:alnum:]_])creat\(|=[[:space:]]*creat[[:space:]]*$'
scan_pattern 'truncate' '(^|[^[:alnum:]_])truncate\(|=[[:space:]]*truncate[[:space:]]*$'
scan_pattern 'ftruncate' '(^|[^[:alnum:]_])ftruncate\(|=[[:space:]]*ftruncate[[:space:]]*$'
scan_pattern 'setxattr' '(^|[^[:alnum:]_])setxattr\(|=[[:space:]]*setxattr[[:space:]]*$'
scan_pattern 'removexattr' '(^|[^[:alnum:]_])removexattr\(|=[[:space:]]*removexattr[[:space:]]*$'
scan_pattern 'fsetxattr' '(^|[^[:alnum:]_])fsetxattr\(|=[[:space:]]*fsetxattr[[:space:]]*$'
scan_pattern 'fremovexattr' '(^|[^[:alnum:]_])fremovexattr\(|=[[:space:]]*fremovexattr[[:space:]]*$'
scan_pattern 'Darwin.write' 'Darwin\.write\(|=[[:space:]]*Darwin\.write[[:space:]]*$'
scan_pattern 'write' '(^|[^[:alnum:]_.])write\(|=[[:space:]]*write[[:space:]]*$'
scan_pattern 'pwrite' '(^|[^[:alnum:]_])pwrite\(|=[[:space:]]*pwrite[[:space:]]*$'
scan_pattern 'writev' '(^|[^[:alnum:]_])writev\(|=[[:space:]]*writev[[:space:]]*$'
scan_pattern 'Foundation URL write' '\.write\(to:'
scan_pattern 'O_CREAT' 'O_CREAT'
scan_pattern 'O_TRUNC' 'O_TRUNC'

if ! sort -u "$MATCHES_FILE" > "$SORTED_MATCHES_FILE"; then
  fail "unable to sort filesystem mutation matches"
fi

violations=0

while IFS= read -r match; do
  [[ -z "$match" ]] && continue

  mutation="${match%%$'\t'*}"
  detail="${match#*$'\t'}"
  if [[ "$detail" == "$match" ]]; then
    fail "malformed filesystem mutation match"
  fi

  file="${detail%%:*}"
  rest="${detail#*:}"
  line="${rest%%:*}"
  text="${rest#*:}"

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/InternalStagingCommitter.swift"* ]] \
     && [[ "$mutation" == 'FileManager moveItem' ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/SafeFileCopyEngine.swift"* ]] \
     && [[ "$mutation" == 'FileManager copyItem' ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/PinnedDestinationStagingCommitter.swift"* ]] \
     && [[ "$mutation" == 'renameatx_np' ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/OwnedStagingRecoveryCleaner.swift"* ]] \
     && [[ "$mutation" == 'FileManager removeItem' ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/SourceFileLeaseRegistry.swift"* ]] \
     && { [[ "$mutation" == 'fcopyfile' ]] || [[ "$mutation" == 'O_CREAT' ]]; }; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/PendingCopyFileIdentity.swift"* ]] \
     && { [[ "$mutation" == 'fsetxattr' ]] || [[ "$mutation" == 'fremovexattr' ]]; }; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassPersistenceAdapter/ApplicationProcessLock.swift"* ]] \
     && [[ "$mutation" == 'O_CREAT' ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassPOSIXSupport/PhysicalStateStore.swift"* ]] \
     && { [[ "$mutation" == 'O_CREAT' ]] \
          || [[ "$mutation" == 'mkdirat' ]] \
          || [[ "$mutation" == 'renameat' ]] \
          || [[ "$mutation" == 'unlinkat' ]] \
          || [[ "$mutation" == 'Darwin.write' ]]; }; then
    continue
  fi

  echo "File safety violation: ${file#$ROOT/}:$line:$text" >&2
  violations=1
done < "$SORTED_MATCHES_FILE"

exit "$violations"
