#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-build-history-key-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin" "$FIXTURE/history/one"

CURRENT="$FIXTURE/current.txt"
HISTORICAL="$FIXTURE/history/one/RELEASE_EVIDENCE.txt"
REAL_GREP="$(command -v grep)"

cat > "$CURRENT" <<'EOF'
schema_version=1
bundle_build=5
EOF

cat > "$HISTORICAL" <<'EOF'
schema_version=1
bundle_build=4
EOF

# Control: valid monotonic history remains accepted with the real grep.
bash Scripts/verify-release-build-history.sh "$CURRENT" "$FIXTURE/history" >/dev/null

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == '-c' ]] || {
  echo "fixture: unexpected grep invocation: $*" >&2
  exit 91
}

target="${@: -1}"

case "${BUILD_HISTORY_GREP_FIXTURE_MODE:?}" in
  current-failure)
    printf '1\n'
    echo 'fixture: current release evidence key enumeration unavailable after partial count' >&2
    exit 42
    ;;
  historical-failure)
    if [[ "$target" == */history/* ]]; then
      printf '1\n'
      echo 'fixture: historical release evidence key enumeration unavailable after partial count' >&2
      exit 42
    fi
    exec "$REAL_GREP" "$@"
    ;;
  malformed)
    printf 'not-a-count\n'
    exit 0
    ;;
  *)
    echo "fixture: unexpected grep mode: ${BUILD_HISTORY_GREP_FIXTURE_MODE:-}" >&2
    exit 92
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/grep"

run_failure_case() {
  local mode="$1"
  local output="$2"
  local expected_fragment="$3"

  set +e
  BUILD_HISTORY_GREP_FIXTURE_MODE="$mode" \
    REAL_GREP="$REAL_GREP" \
    PATH="$FIXTURE/bin:$PATH" \
    bash Scripts/verify-release-build-history.sh "$CURRENT" "$FIXTURE/history" \
    >"$output" 2>&1
  local status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    cat "$output"
    echo "Release build-history validator unexpectedly accepted fixture mode: $mode" >&2
    exit 1
  fi

  "$REAL_GREP" -Fq "$expected_fragment" "$output"
}

CURRENT_FAILURE_OUTPUT="$FIXTURE/current-failure.log"
run_failure_case \
  'current-failure' \
  "$CURRENT_FAILURE_OUTPUT" \
  'Release build history validation failed: unable to enumerate schema_version in release evidence'
"$REAL_GREP" -Fq '(grep status 42)' "$CURRENT_FAILURE_OUTPUT"
"$REAL_GREP" -Fq "$CURRENT" "$CURRENT_FAILURE_OUTPUT"

HISTORICAL_FAILURE_OUTPUT="$FIXTURE/historical-failure.log"
run_failure_case \
  'historical-failure' \
  "$HISTORICAL_FAILURE_OUTPUT" \
  'Release build history validation failed: unable to enumerate schema_version in release evidence'
"$REAL_GREP" -Fq '(grep status 42)' "$HISTORICAL_FAILURE_OUTPUT"
"$REAL_GREP" -Fq "$HISTORICAL" "$HISTORICAL_FAILURE_OUTPUT"

MALFORMED_OUTPUT="$FIXTURE/malformed.log"
run_failure_case \
  'malformed' \
  "$MALFORMED_OUTPUT" \
  'Release build history validation failed: release evidence key count is not numeric for schema_version'
"$REAL_GREP" -Fq 'not-a-count' "$MALFORMED_OUTPUT"

rm -rf "$FIXTURE"
echo 'Release build-history key-enumeration failure fixtures passed'
