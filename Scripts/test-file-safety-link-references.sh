#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-link-reference-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"
OUTPUT="$FIXTURE/output.log"
LOCK_SOURCE="$ROOT/Packages/SchneeGlassKit/Sources/SchneeGlassPersistenceAdapter/ApplicationProcessLock.swift"
LOCK_BACKUP="$FIXTURE/ApplicationProcessLock.swift.backup"
REAL_GREP="$(command -v grep)"

cleanup() {
  if [[ -f "$LOCK_BACKUP" ]]; then
    cp "$LOCK_BACKUP" "$LOCK_SOURCE"
  fi
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

cp "$LOCK_SOURCE" "$LOCK_BACKUP"

# Keep all twenty negative fixtures in one guard scan. Every API/context
# combination gets a unique diagnostic marker, so a failed guard cannot pass
# this fixture merely because some *other* operation was rejected.
EXPECTED_MARKERS=()
cp "$LOCK_BACKUP" "$LOCK_SOURCE"

FAILURES=0
for link_reference_case in link linkat symlink symlinkat; do
  for reference_context in assignment argument labeledArgument array return; do
    marker="FILE_SAFETY_LINK_${link_reference_case}_${reference_context}"
    case "$reference_context" in
      assignment)
        source_line="private let $marker = $link_reference_case"
        ;;
      argument)
        source_line="private let $marker = consume($link_reference_case)"
        ;;
      labeledArgument)
        source_line="private let $marker = consume(callback: $link_reference_case)"
        ;;
      array)
        source_line="private let $marker = [$link_reference_case]"
        ;;
      return)
        source_line="private let $marker = { return $link_reference_case }"
        ;;
    esac

    printf '%s\\n' "$source_line" >> "$LOCK_SOURCE"
    EXPECTED_MARKERS+=("$marker")
  done
done

# Exactly 4 APIs × 5 reference contexts must remain covered.
if [[ "${#EXPECTED_MARKERS[@]}" -ne 20 ]]; then
  echo 'Unexpected POSIX link reference fixture count.' >&2
  exit 1
fi

set +e
bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
batched_status=$?
set -e

if [[ "$batched_status" -eq 0 ]]; then
  echo 'File Safety Guard unexpectedly allowed batched POSIX link references.' >&2
  exit 1
fi

if ! "$REAL_GREP" -Fq 'ApplicationProcessLock.swift' "$OUTPUT"; then
  echo 'File Safety Guard failed without source-level link diagnostics.' >&2
  exit 1
fi

for marker in "${EXPECTED_MARKERS[@]}"; do
  matches=$("$REAL_GREP" -Fc "$marker" "$OUTPUT" || true)
  if [[ "$matches" -ne 1 ]]; then
    echo "Expected exactly one File Safety diagnostic for: $marker (found $matches)" >&2
    ((FAILURES += 1))
  fi
done

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES POSIX link function-reference fixture(s) were not detected." >&2
  exit 1
fi

echo 'POSIX link function-reference fixtures passed'
