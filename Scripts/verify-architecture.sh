#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
SRC="$ROOT/Packages/SchneeGlassKit/Sources"
APP="$ROOT/App"

fail() {
  echo "Architecture verification failed: $*" >&2
  exit 1
}

TMP_BASE="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
SCAN_FILE="$(mktemp "$TMP_BASE/schneeglass-architecture-scan.XXXXXX")"
cleanup() {
  rm -f "$SCAN_FILE"
}
trap cleanup EXIT

scan_pattern() {
  local label="$1"
  local dir="$2"
  local pattern="$3"
  local emit_matches="${4:-true}"
  local status

  : > "$SCAN_FILE"
  set +e
  grep -RInE "$pattern" "$dir" --include='*.swift' > "$SCAN_FILE"
  status=$?
  set -e

  case "$status" in
    0)
      if [[ "$emit_matches" == 'true' ]]; then
        cat "$SCAN_FILE" || fail "unable to read architecture scan results: $label"
      fi
      return 0
      ;;
    1)
      return 1
      ;;
    *)
      fail "unable to enumerate $label (grep status $status)"
      ;;
  esac
}

violations=0

check_forbidden_imports() {
  local label="$1"
  local dir="$2"
  local pattern="$3"

  if scan_pattern "$label" "$dir" "^[[:space:]]*import[[:space:]]+(${pattern})$"; then
    echo "Architecture violation: forbidden import in ${dir#$ROOT/}" >&2
    violations=1
  fi
}

check_forbidden_imports \
  'SchneeGlassDomain forbidden imports' \
  "$SRC/SchneeGlassDomain" \
  'SwiftUI|AppKit|CoreServices|GRDB|SchneeGlassPOSIXSupport'
check_forbidden_imports \
  'FileDomain forbidden imports' \
  "$SRC/FileDomain" \
  'SwiftUI|AppKit|CoreServices|GRDB|SchneeGlassPOSIXSupport'
check_forbidden_imports \
  'SchneeGlassDesignSystem forbidden imports' \
  "$SRC/SchneeGlassDesignSystem" \
  'AppKit|CoreServices|GRDB|SchneeGlassDomain|FileDomain|SchneeGlassApplication|SchneeGlassPresentation|SchneeGlassPOSIXSupport|SchneeGlassFileSystemAdapter|SchneeGlassPersistenceAdapter|SchneeGlassMacOSAdapter'
check_forbidden_imports \
  'SchneeGlassPresentation forbidden imports' \
  "$SRC/SchneeGlassPresentation" \
  'SchneeGlassFileSystemAdapter|SchneeGlassPersistenceAdapter|SchneeGlassPOSIXSupport'
check_forbidden_imports \
  'SchneeGlassPOSIXSupport forbidden imports' \
  "$SRC/SchneeGlassPOSIXSupport" \
  'SwiftUI|AppKit|CoreServices|GRDB|SchneeGlassDomain|FileDomain|SchneeGlassApplication|SchneeGlassPresentation|SchneeGlassFileSystemAdapter|SchneeGlassPersistenceAdapter|SchneeGlassMacOSAdapter'

if scan_pattern \
  'App native Drop/copy implementation symbols' \
  "$APP" \
  '\b(SourceFileLeaseRegistry|NativeDropPlanningAdapter|PinnedSourceFileCopying)\b'; then
  echo 'Architecture violation: App must compose native Drop planning/copying through PinnedDropCopyPipeline.' >&2
  violations=1
fi

if scan_pattern \
  'unauthorized @unchecked Sendable declarations' \
  "$SRC" \
  '(^|[^A-Za-z0-9_])@unchecked[[:space:]]+Sendable'; then
  echo 'Architecture violation: @unchecked Sendable requires an approved ADR.' >&2
  violations=1
fi

if scan_pattern \
  'private CGS symbols' \
  "$SRC" \
  '\bCGS[A-Za-z0-9_]+'; then
  echo 'Architecture violation: private CGS symbol detected.' >&2
  violations=1
fi

if scan_pattern 'TODO/FIXME policy markers' "$SRC" '\b(TODO|FIXME)\b' false; then
  while IFS= read -r match; do
    [[ -n "$match" ]] || continue
    if [[ ! "$match" =~ (TODO|FIXME)\(#[0-9]+\) ]]; then
      printf '%s\n' "$match"
      echo 'Policy violation: TODO/FIXME in Swift sources must reference an issue.' >&2
      violations=1
    fi
  done < "$SCAN_FILE"
fi

exit "$violations"
