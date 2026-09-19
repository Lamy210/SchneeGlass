#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-architecture-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
REAL_GREP="$(command -v grep)"

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

MODE="${ARCH_FIXTURE_MODE:?}"
ARGS="$*"

case "$MODE" in
  partial-failure)
    if [[ "$ARGS" == *'TODO|FIXME'* ]]; then
      exit 1
    fi
    printf '%s\n' \
      '/tmp/SchneeGlassFixture/Packages/SchneeGlassKit/Sources/SchneeGlassDomain/Forbidden.swift:1:import AppKit'
    echo 'fixture: architecture enumeration unavailable after partial output' >&2
    exit 42
    ;;
  no-match)
    exit 1
    ;;
  forbidden-import)
    if [[ "$ARGS" == *'SchneeGlassDomain'* && "$ARGS" == *'import'* ]]; then
      printf '%s\n' \
        '/tmp/SchneeGlassFixture/Packages/SchneeGlassKit/Sources/SchneeGlassDomain/Forbidden.swift:1:import AppKit'
      exit 0
    fi
    exit 1
    ;;
  invalid-todo)
    if [[ "$ARGS" == *'TODO|FIXME'* ]]; then
      printf '%s\n' \
        '/tmp/SchneeGlassFixture/Packages/SchneeGlassKit/Sources/SchneeGlassDomain/Todo.swift:1:// TODO fix this'
      exit 0
    fi
    exit 1
    ;;
  valid-todo)
    if [[ "$ARGS" == *'TODO|FIXME'* ]]; then
      printf '%s\n' \
        '/tmp/SchneeGlassFixture/Packages/SchneeGlassKit/Sources/SchneeGlassDomain/Todo.swift:1:// TODO(#123) fix this'
      exit 0
    fi
    exit 1
    ;;
  *)
    echo "unexpected architecture fixture mode: $MODE" >&2
    exit 90
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/grep"

run_guard() {
  local mode="$1"
  local output="$2"
  set +e
  ARCH_FIXTURE_MODE="$mode" \
    PATH="$FIXTURE/bin:$PATH" \
    bash Scripts/verify-architecture.sh >"$output" 2>&1
  local status=$?
  set -e
  printf '%s' "$status"
}

OUTPUT_FAILURE="$FIXTURE/partial-failure.log"
STATUS="$(run_guard partial-failure "$OUTPUT_FAILURE")"
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_FAILURE"
  echo 'Architecture Guard unexpectedly accepted partial enumeration after grep failure.' >&2
  exit 1
fi
"$REAL_GREP" -Fq \
  'Architecture verification failed: unable to enumerate' \
  "$OUTPUT_FAILURE"

OUTPUT_NO_MATCH="$FIXTURE/no-match.log"
STATUS="$(run_guard no-match "$OUTPUT_NO_MATCH")"
if [[ "$STATUS" -ne 0 ]]; then
  cat "$OUTPUT_NO_MATCH"
  echo 'Architecture Guard rejected legitimate no-match scan results.' >&2
  exit 1
fi

OUTPUT_FORBIDDEN="$FIXTURE/forbidden-import.log"
STATUS="$(run_guard forbidden-import "$OUTPUT_FORBIDDEN")"
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_FORBIDDEN"
  echo 'Architecture Guard accepted a forbidden Domain import.' >&2
  exit 1
fi
"$REAL_GREP" -Fq 'Architecture violation: forbidden import in' "$OUTPUT_FORBIDDEN"

OUTPUT_INVALID_TODO="$FIXTURE/invalid-todo.log"
STATUS="$(run_guard invalid-todo "$OUTPUT_INVALID_TODO")"
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_INVALID_TODO"
  echo 'Architecture Guard accepted a TODO without an issue reference.' >&2
  exit 1
fi
"$REAL_GREP" -Fq \
  'Policy violation: TODO/FIXME in Swift sources must reference an issue.' \
  "$OUTPUT_INVALID_TODO"

OUTPUT_VALID_TODO="$FIXTURE/valid-todo.log"
STATUS="$(run_guard valid-todo "$OUTPUT_VALID_TODO")"
if [[ "$STATUS" -ne 0 ]]; then
  cat "$OUTPUT_VALID_TODO"
  echo 'Architecture Guard rejected an issue-linked TODO.' >&2
  exit 1
fi

rm -rf "$FIXTURE"
echo 'Architecture Guard enumeration and policy fixtures passed'
