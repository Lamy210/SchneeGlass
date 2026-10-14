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
scan_pattern 'link' '(^|[^[:alnum:]_])link\(|=[[:space:]]*link[[:space:]]*$|(\(|\[|,|:)[[:space:]]*link[[:space:]]*(\)|\]|,)|return[[:space:]]+link([^[:alnum:]_]|$)'
scan_pattern 'linkat' '(^|[^[:alnum:]_])linkat\(|=[[:space:]]*linkat[[:space:]]*$|(\(|\[|,|:)[[:space:]]*linkat[[:space:]]*(\)|\]|,)|return[[:space:]]+linkat([^[:alnum:]_]|$)'
scan_pattern 'symlink' '(^|[^[:alnum:]_])symlink\(|=[[:space:]]*symlink[[:space:]]*$|(\(|\[|,|:)[[:space:]]*symlink[[:space:]]*(\)|\]|,)|return[[:space:]]+symlink([^[:alnum:]_]|$)'
scan_pattern 'symlinkat' '(^|[^[:alnum:]_])symlinkat\(|=[[:space:]]*symlinkat[[:space:]]*$|(\(|\[|,|:)[[:space:]]*symlinkat[[:space:]]*(\)|\]|,)|return[[:space:]]+symlinkat([^[:alnum:]_]|$)'
scan_pattern 'unlink' '(^|[^[:alnum:]_])unlink([^[:alnum:]_]|$)'
scan_pattern 'unlinkat' '(^|[^[:alnum:]_])unlinkat([^[:alnum:]_]|$)'
scan_pattern 'rmdir' '(^|[^[:alnum:]_])rmdir([^[:alnum:]_]|$)'
scan_pattern 'rename' '(^|[^[:alnum:]_])rename\(|=[[:space:]]*rename[[:space:]]*$|\([[:space:]]*rename[[:space:]]*\)|:[[:space:]]*rename[[:space:]]*\)|\[[[:space:]]*rename[[:space:]]*\]|return[[:space:]]+rename([^[:alnum:]_]|$)'
scan_pattern 'renameat' '(^|[^[:alnum:]_])renameat\(|=[[:space:]]*renameat[[:space:]]*$|\([[:space:]]*renameat[[:space:]]*\)|:[[:space:]]*renameat[[:space:]]*\)|\[[[:space:]]*renameat[[:space:]]*\]|return[[:space:]]+renameat([^[:alnum:]_]|$)'
scan_pattern 'renameatx_np' '(^|[^[:alnum:]_])renameatx_np\(|=[[:space:]]*renameatx_np[[:space:]]*$|\([[:space:]]*renameatx_np[[:space:]]*\)|:[[:space:]]*renameatx_np[[:space:]]*\)|\[[[:space:]]*renameatx_np[[:space:]]*\]|return[[:space:]]+renameatx_np([^[:alnum:]_]|$)'
scan_pattern 'renamex_np' '(^|[^[:alnum:]_])renamex_np\(|=[[:space:]]*renamex_np[[:space:]]*$|\([[:space:]]*renamex_np[[:space:]]*\)|:[[:space:]]*renamex_np[[:space:]]*\)|\[[[:space:]]*renamex_np[[:space:]]*\]|return[[:space:]]+renamex_np([^[:alnum:]_]|$)'
scan_pattern 'mkdir' '(^|[^[:alnum:]_])mkdir\(|=[[:space:]]*mkdir[[:space:]]*$|\([[:space:]]*mkdir[[:space:]]*\)|:[[:space:]]*mkdir[[:space:]]*\)|\[[[:space:]]*mkdir[[:space:]]*\]|return[[:space:]]+mkdir([^[:alnum:]_]|$)'
scan_pattern 'mkdirat' '(^|[^[:alnum:]_])mkdirat\(|=[[:space:]]*mkdirat[[:space:]]*$|\([[:space:]]*mkdirat[[:space:]]*\)|:[[:space:]]*mkdirat[[:space:]]*\)|\[[[:space:]]*mkdirat[[:space:]]*\]|return[[:space:]]+mkdirat([^[:alnum:]_]|$)'
scan_pattern 'chmod' '(^|[^[:alnum:]_])chmod\(|=[[:space:]]*chmod[[:space:]]*$|\([[:space:]]*chmod[[:space:]]*\)|:[[:space:]]*chmod[[:space:]]*\)|\[[[:space:]]*chmod[[:space:]]*\]|return[[:space:]]+chmod([^[:alnum:]_]|$)'
scan_pattern 'fchmod' '(^|[^[:alnum:]_])fchmod\(|=[[:space:]]*fchmod[[:space:]]*$|\([[:space:]]*fchmod[[:space:]]*\)|:[[:space:]]*fchmod[[:space:]]*\)|\[[[:space:]]*fchmod[[:space:]]*\]|return[[:space:]]+fchmod([^[:alnum:]_]|$)'
scan_pattern 'fchmodat' '(^|[^[:alnum:]_])fchmodat\(|=[[:space:]]*fchmodat[[:space:]]*$|\([[:space:]]*fchmodat[[:space:]]*\)|:[[:space:]]*fchmodat[[:space:]]*\)|\[[[:space:]]*fchmodat[[:space:]]*\]|return[[:space:]]+fchmodat([^[:alnum:]_]|$)'
scan_pattern 'chown' '(^|[^[:alnum:]_])chown\(|=[[:space:]]*chown[[:space:]]*$|\([[:space:]]*chown[[:space:]]*\)|:[[:space:]]*chown[[:space:]]*\)|\[[[:space:]]*chown[[:space:]]*\]|return[[:space:]]+chown([^[:alnum:]_]|$)'
scan_pattern 'fchown' '(^|[^[:alnum:]_])fchown\(|=[[:space:]]*fchown[[:space:]]*$|\([[:space:]]*fchown[[:space:]]*\)|:[[:space:]]*fchown[[:space:]]*\)|\[[[:space:]]*fchown[[:space:]]*\]|return[[:space:]]+fchown([^[:alnum:]_]|$)'
scan_pattern 'lchown' '(^|[^[:alnum:]_])lchown\(|=[[:space:]]*lchown[[:space:]]*$|\([[:space:]]*lchown[[:space:]]*\)|:[[:space:]]*lchown[[:space:]]*\)|\[[[:space:]]*lchown[[:space:]]*\]|return[[:space:]]+lchown([^[:alnum:]_]|$)'
scan_pattern 'fchownat' '(^|[^[:alnum:]_])fchownat\(|=[[:space:]]*fchownat[[:space:]]*$|\([[:space:]]*fchownat[[:space:]]*\)|:[[:space:]]*fchownat[[:space:]]*\)|\[[[:space:]]*fchownat[[:space:]]*\]|return[[:space:]]+fchownat([^[:alnum:]_]|$)'
scan_pattern 'chflags' '(^|[^[:alnum:]_])chflags\(|=[[:space:]]*chflags[[:space:]]*$|\([[:space:]]*chflags[[:space:]]*\)|:[[:space:]]*chflags[[:space:]]*\)|\[[[:space:]]*chflags[[:space:]]*\]|return[[:space:]]+chflags([^[:alnum:]_]|$)'
scan_pattern 'fchflags' '(^|[^[:alnum:]_])fchflags\(|=[[:space:]]*fchflags[[:space:]]*$|\([[:space:]]*fchflags[[:space:]]*\)|:[[:space:]]*fchflags[[:space:]]*\)|\[[[:space:]]*fchflags[[:space:]]*\]|return[[:space:]]+fchflags([^[:alnum:]_]|$)'
scan_pattern 'lchflags' '(^|[^[:alnum:]_])lchflags\(|=[[:space:]]*lchflags[[:space:]]*$|\([[:space:]]*lchflags[[:space:]]*\)|:[[:space:]]*lchflags[[:space:]]*\)|\[[[:space:]]*lchflags[[:space:]]*\]|return[[:space:]]+lchflags([^[:alnum:]_]|$)'
scan_pattern 'fcopyfile' '(^|[^[:alnum:]_])fcopyfile\(|=[[:space:]]*fcopyfile[[:space:]]*$|(\(|\[|,|:)[[:space:]]*fcopyfile[[:space:]]*(\)|\]|,)|return[[:space:]]+fcopyfile([^[:alnum:]_]|$)'
scan_pattern 'copyfile' '(^|[^[:alnum:]_])copyfile\(|=[[:space:]]*copyfile[[:space:]]*$|\([[:space:]]*copyfile[[:space:]]*\)|:[[:space:]]*copyfile[[:space:]]*\)|\[[[:space:]]*copyfile[[:space:]]*\]|return[[:space:]]+copyfile([^[:alnum:]_]|$)'
scan_pattern 'clonefile' '(^|[^[:alnum:]_])clonefile\(|=[[:space:]]*clonefile[[:space:]]*$|(\(|\[|,|:)[[:space:]]*clonefile[[:space:]]*(\)|\]|,)|return[[:space:]]+clonefile([^[:alnum:]_]|$)'
scan_pattern 'clonefileat' '(^|[^[:alnum:]_])clonefileat\(|=[[:space:]]*clonefileat[[:space:]]*$|(\(|\[|,|:)[[:space:]]*clonefileat[[:space:]]*(\)|\]|,)|return[[:space:]]+clonefileat([^[:alnum:]_]|$)'
scan_pattern 'fclonefileat' '(^|[^[:alnum:]_])fclonefileat\(|=[[:space:]]*fclonefileat[[:space:]]*$|(\(|\[|,|:)[[:space:]]*fclonefileat[[:space:]]*(\)|\]|,)|return[[:space:]]+fclonefileat([^[:alnum:]_]|$)'
scan_pattern 'creat' '(^|[^[:alnum:]_])creat\(|=[[:space:]]*creat[[:space:]]*$|(\(|\[|,)[[:space:]]*creat[[:space:]]*(\)|\]|,)|return[[:space:]]+creat([^[:alnum:]_]|$)'
scan_pattern 'truncate' '(^|[^[:alnum:]_])truncate\(|=[[:space:]]*truncate[[:space:]]*$|(\(|\[|,)[[:space:]]*truncate[[:space:]]*(\)|\]|,)|return[[:space:]]+truncate([^[:alnum:]_]|$)'
scan_pattern 'ftruncate' '(^|[^[:alnum:]_])ftruncate\(|=[[:space:]]*ftruncate[[:space:]]*$|(\(|\[|,)[[:space:]]*ftruncate[[:space:]]*(\)|\]|,)|return[[:space:]]+ftruncate([^[:alnum:]_]|$)'
scan_pattern 'setxattr' '(^|[^[:alnum:]_])setxattr\(|=[[:space:]]*setxattr[[:space:]]*$|(\(|\[|,)[[:space:]]*setxattr[[:space:]]*(\)|\]|,)|return[[:space:]]+setxattr([^[:alnum:]_]|$)'
scan_pattern 'removexattr' '(^|[^[:alnum:]_])removexattr\(|=[[:space:]]*removexattr[[:space:]]*$|(\(|\[|,)[[:space:]]*removexattr[[:space:]]*(\)|\]|,)|return[[:space:]]+removexattr([^[:alnum:]_]|$)'
scan_pattern 'fsetxattr' '(^|[^[:alnum:]_])fsetxattr\(|=[[:space:]]*fsetxattr[[:space:]]*$|(\(|\[|,)[[:space:]]*fsetxattr[[:space:]]*(\)|\]|,)|return[[:space:]]+fsetxattr([^[:alnum:]_]|$)'
scan_pattern 'fremovexattr' '(^|[^[:alnum:]_])fremovexattr\(|=[[:space:]]*fremovexattr[[:space:]]*$|(\(|\[|,)[[:space:]]*fremovexattr[[:space:]]*(\)|\]|,)|return[[:space:]]+fremovexattr([^[:alnum:]_]|$)'
scan_pattern 'utime' '(^|[^[:alnum:]_])utime\(|=[[:space:]]*utime[[:space:]]*$|\([[:space:]]*utime[[:space:]]*\)|:[[:space:]]*utime[[:space:]]*\)|\[[[:space:]]*utime[[:space:]]*\]|return[[:space:]]+utime([^[:alnum:]_]|$)'
scan_pattern 'utimes' '(^|[^[:alnum:]_])utimes\(|=[[:space:]]*utimes[[:space:]]*$|\([[:space:]]*utimes[[:space:]]*\)|:[[:space:]]*utimes[[:space:]]*\)|\[[[:space:]]*utimes[[:space:]]*\]|return[[:space:]]+utimes([^[:alnum:]_]|$)'
scan_pattern 'futimes' '(^|[^[:alnum:]_])futimes\(|=[[:space:]]*futimes[[:space:]]*$|\([[:space:]]*futimes[[:space:]]*\)|:[[:space:]]*futimes[[:space:]]*\)|\[[[:space:]]*futimes[[:space:]]*\]|return[[:space:]]+futimes([^[:alnum:]_]|$)'
scan_pattern 'lutimes' '(^|[^[:alnum:]_])lutimes\(|=[[:space:]]*lutimes[[:space:]]*$|\([[:space:]]*lutimes[[:space:]]*\)|:[[:space:]]*lutimes[[:space:]]*\)|\[[[:space:]]*lutimes[[:space:]]*\]|return[[:space:]]+lutimes([^[:alnum:]_]|$)'
scan_pattern 'futimens' '(^|[^[:alnum:]_])futimens\(|=[[:space:]]*futimens[[:space:]]*$|\([[:space:]]*futimens[[:space:]]*\)|:[[:space:]]*futimens[[:space:]]*\)|\[[[:space:]]*futimens[[:space:]]*\]|return[[:space:]]+futimens([^[:alnum:]_]|$)'
scan_pattern 'utimensat' '(^|[^[:alnum:]_])utimensat\(|=[[:space:]]*utimensat[[:space:]]*$|\([[:space:]]*utimensat[[:space:]]*\)|:[[:space:]]*utimensat[[:space:]]*\)|\[[[:space:]]*utimensat[[:space:]]*\]|return[[:space:]]+utimensat([^[:alnum:]_]|$)'
scan_pattern 'Darwin.write' 'Darwin\.write\(|=[[:space:]]*Darwin\.write[[:space:]]*$|(\(|\[|,|:)[[:space:]]*Darwin\.write[[:space:]]*(\)|\]|,)|return[[:space:]]+Darwin\.write([^[:alnum:]_]|$)'
scan_pattern 'write' '(^|[^[:alnum:]_.])write\(|=[[:space:]]*write[[:space:]]*$|(\(|\[|,|:)[[:space:]]*write[[:space:]]*(\)|\]|,)|return[[:space:]]+write([^[:alnum:]_]|$)'
scan_pattern 'pwrite' '(^|[^[:alnum:]_])pwrite\(|=[[:space:]]*pwrite[[:space:]]*$|(\(|\[|,|:)[[:space:]]*pwrite[[:space:]]*(\)|\]|,)|return[[:space:]]+pwrite([^[:alnum:]_]|$)'
scan_pattern 'writev' '(^|[^[:alnum:]_])writev\(|=[[:space:]]*writev[[:space:]]*$|(\(|\[|,|:)[[:space:]]*writev[[:space:]]*(\)|\]|,)|return[[:space:]]+writev([^[:alnum:]_]|$)'
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
