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
scan_pattern 'FileManager removeItem' '\.removeItem\('
scan_pattern 'FileManager moveItem' '\.moveItem\('
scan_pattern 'FileManager replaceItem' '\.replaceItem\('
scan_pattern 'unlink' '(^|[^[:alnum:]_])unlink\('
scan_pattern 'unlinkat' '(^|[^[:alnum:]_])unlinkat\('
scan_pattern 'renameat' '(^|[^[:alnum:]_])renameat\('
scan_pattern 'renameatx_np' '(^|[^[:alnum:]_])renameatx_np\('
scan_pattern 'mkdirat' '(^|[^[:alnum:]_])mkdirat\('
scan_pattern 'fcopyfile' '(^|[^[:alnum:]_])fcopyfile\('
scan_pattern 'creat' '(^|[^[:alnum:]_])creat\('
scan_pattern 'truncate' '(^|[^[:alnum:]_])truncate\('
scan_pattern 'ftruncate' '(^|[^[:alnum:]_])ftruncate\('
scan_pattern 'Darwin.write' 'Darwin\.write\('
scan_pattern 'write' '(^|[^[:alnum:]_.])write\('
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
