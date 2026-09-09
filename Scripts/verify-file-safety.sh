#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/Packages/SchneeGlassKit/Sources"

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

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/OwnedStagingRecoveryCleaner.swift"* ]] \
     && [[ "$text" == *".removeItem("* ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassPersistenceAdapter/ConfigurationBackupRotator.swift"* ]] \
     && [[ "$text" == *"unlink("* ]]; then
    continue
  fi

  if [[ "$file" == *"/SchneeGlassFileSystemAdapter/SourceFileLeaseRegistry.swift"* ]] \
     && { [[ "$text" == *"fcopyfile("* ]] || [[ "$text" == *"O_CREAT"* ]]; }; then
    continue
  fi

  echo "File safety violation: ${file#$ROOT/}:$line:$text" >&2
  violations=1
done < <(
  {
    grep -RInE '\.(removeItem|moveItem|replaceItem)\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])unlink\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])fcopyfile\(' "$SRC" --include='*.swift' || true
    grep -RInE 'O_CREAT' "$SRC" --include='*.swift' || true
  } | sort -u
)

exit "$violations"
