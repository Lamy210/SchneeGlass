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
done < <(
  {
    grep -RInE '\.(removeItem|moveItem|replaceItem)\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])unlink\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])unlinkat\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])renameat\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])renameatx_np\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])mkdirat\(' "$SRC" --include='*.swift' || true
    grep -RInE '(^|[^[:alnum:]_])fcopyfile\(' "$SRC" --include='*.swift' || true
    grep -RInE 'O_CREAT' "$SRC" --include='*.swift' || true
  } | sort -u
)

exit "$violations"
