#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/Packages/SchneeGlassKit/Sources"
APP="$ROOT/App"
fail=0

check_forbidden_imports() {
  local dir="$1"
  local pattern="$2"

  if grep -RInE "^[[:space:]]*import[[:space:]]+(${pattern})$" "$dir" --include='*.swift'; then
    echo "Architecture violation: forbidden import in ${dir#$ROOT/}" >&2
    fail=1
  fi
}

check_forbidden_imports "$SRC/SchneeGlassDomain" 'SwiftUI|AppKit|CoreServices|GRDB|SchneeGlassPOSIXSupport'
check_forbidden_imports "$SRC/FileDomain" 'SwiftUI|AppKit|CoreServices|GRDB|SchneeGlassPOSIXSupport'
check_forbidden_imports "$SRC/SchneeGlassPresentation" 'SchneeGlassFileSystemAdapter|SchneeGlassPersistenceAdapter|SchneeGlassPOSIXSupport'
check_forbidden_imports "$SRC/SchneeGlassPOSIXSupport" 'SwiftUI|AppKit|CoreServices|GRDB|SchneeGlassDomain|FileDomain|SchneeGlassApplication|SchneeGlassPresentation|SchneeGlassFileSystemAdapter|SchneeGlassPersistenceAdapter|SchneeGlassMacOSAdapter'

if grep -RInE '\b(SourceFileLeaseRegistry|NativeDropPlanningAdapter|PinnedSourceFileCopying)\b' "$APP" --include='*.swift'; then
  echo 'Architecture violation: App must compose native Drop planning/copying through PinnedDropCopyPipeline.' >&2
  fail=1
fi

if grep -RInE '(^|[^A-Za-z0-9_])@unchecked[[:space:]]+Sendable' "$SRC" --include='*.swift'; then
  echo 'Architecture violation: @unchecked Sendable requires an approved ADR.' >&2
  fail=1
fi

if grep -RInE '\bCGS[A-Za-z0-9_]+' "$SRC" --include='*.swift'; then
  echo 'Architecture violation: private CGS symbol detected.' >&2
  fail=1
fi

todo_hits="$(grep -RInE '\b(TODO|FIXME)\b' "$SRC" --include='*.swift' || true)"
if [[ -n "$todo_hits" ]]; then
  invalid_todos="$(printf '%s\n' "$todo_hits" | grep -vE '(TODO|FIXME)\(#[0-9]+\)' || true)"
  if [[ -n "$invalid_todos" ]]; then
    printf '%s\n' "$invalid_todos"
    echo 'Policy violation: TODO/FIXME in Swift sources must reference an issue.' >&2
    fail=1
  fi
fi

exit "$fail"
