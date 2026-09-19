#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/Packages/SchneeGlassKit/Sources"

fail() {
  echo "File safety verification failed: $*" >&2
  exit 1
}

TMP_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
MATCHES_FILE="$(mktemp "$TMP_BASE/schneeglass-file-safety-matches.XXXXXX")"
SORTED_MATCHES_FILE="$(mktemp "$TMP_BASE/schneeglass-file-safety-sorted.XXXXXX")"
cleanup() {
  rm -f "$MATCHES_FILE" "$SORTED_MATCHES_FILE"
}
trap cleanup EXIT

scan_pattern() {
  local label="$1"
  local pattern="$2"
  local status

  set +e
  grep -RInE "$pattern" "$SRC" --include='*.swift' >> "$MATCHES_FILE"
  status=$?
  set -e

  case "$status" in
    0|1)
      ;;
    *)
      fail "unable to enumerate filesystem mutation pattern: $label (grep status $status)"
      ;;
  esac
}

: > "$MATCHES_FILE"
scan_pattern 'Foundation FileManager mutation' '\.(removeItem|moveItem|replaceItem)\('
scan_pattern 'unlink' '(^|[^[:alnum:]_])unlink\('
scan_pattern 'unlinkat' '(^|[^[:alnum:]_])unlinkat\('
scan_pattern 'renameat' '(^|[^[:alnum:]_])renameat\('
scan_pattern 'renameatx_np' '(^|[^[:alnum:]_])renameatx_np\('
scan_pattern 'mkdirat' '(^|[^[:alnum:]_])mkdirat\('
scan_pattern 'fcopyfile' '(^|[^[:alnum:]_])fcopyfile\('
scan_pattern 'O_CREAT' 'O_CREAT'

if ! sort -u "$MATCHES_FILE" > "$SORTED_MATCHES_FILE"; then
  fail "unable to sort filesystem mutation matches"
fi

violations=0

while IFS= read -r match; do
  [[ -z "$match" ]] && continue

  file="${match%%:*}"
  rest="${match#*:}"
  line="${rest%%:*}"
  text="${rest#*:}"

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/InternalStagingCommitter.swift"* ]] \
     && [[ "$text" == *".moveItem("* ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/PinnedDestinationStagingCommitter.swift"* ]] \
     && [[ "$text" == *"renameatx_np("* ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/OwnedStagingRecoveryCleaner.swift"* ]] \
     && [[ "$text" == *".removeItem("* ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/SourceFileLeaseRegistry.swift"* ]] \
     && { [[ "$text" == *"fcopyfile("* ]] || [[ "$text" == *"O_CREAT"* ]]; }; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassPOSIXSupport/PhysicalStateStore.swift"* ]] \
     && { [[ "$text" == *"O_CREAT"* ]] \
          || [[ "$text" == *"mkdirat("* ]] \
          || [[ "$text" == *"renameat("* ]] \
          || [[ "$text" == *"unlinkat("* ]]; }; then
    continue
  fi

  echo "File safety violation: ${file#$ROOT/}:$line:$text" >&2
  violations=1
done < "$SORTED_MATCHES_FILE"

exit "$violations"
