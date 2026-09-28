#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-production-readiness-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/calls.log"
: > "$LOG"

REAL_BASH="$(command -v bash)"
export REAL_BASH

cat > "$FIXTURE/bin/bash" <<'SHIM'
#!/bin/bash
set -euo pipefail

LOG="${READINESS_FIXTURE_LOG:?}"
MODE="${READINESS_FIXTURE_MODE:-success}"
printf '%q ' "$@" >> "$LOG"
printf '\n' >> "$LOG"

case "${1:-}" in
  Scripts/verify-local-release-source.sh)
    [[ "${2:-}" == 'example/SchneeGlass' ]]
    [[ "$#" -eq 2 ]]
    if [[ "$MODE" == 'source-failure' ]]; then
      echo 'synthetic source failure' >&2
      exit 41
    fi
    echo 'synthetic source verified'
    ;;
  Scripts/setup-release-governance.sh)
    [[ "${2:-}" == 'example/SchneeGlass' ]]
    [[ "${3:-}" == '--verify-only' ]]
    [[ "$#" -eq 3 ]]
    if [[ "$MODE" == 'governance-failure' ]]; then
      echo 'synthetic governance failure' >&2
      exit 42
    fi
    echo 'synthetic governance verified'
    ;;
  Scripts/setup-production-release-environment.sh)
    [[ "${2:-}" == 'example/SchneeGlass' ]]
    [[ "${3:-}" == '--verify-credential-names' ]]
    [[ "$#" -eq 3 ]]
    if [[ "$MODE" == 'environment-failure' ]]; then
      echo 'synthetic Environment failure' >&2
      exit 43
    fi
    echo 'synthetic Environment verified'
    ;;
  *)
    exec "${REAL_BASH:?}" "$@"
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/bash"

export READINESS_FIXTURE_LOG="$LOG"
export PATH="$FIXTURE/bin:$PATH"

assert_count() {
  local expected="$1"
  local pattern="$2"
  local count=''
  local status=0

  set +e
  count="$(grep -Fc -- "$pattern" "$LOG")"
  status=$?
  set -e

  if [[ "$status" -eq 1 ]]; then
    count='0'
  elif [[ "$status" -ne 0 ]]; then
    echo "Unable to enumerate readiness calls for: $pattern (grep status $status)" >&2
    return 1
  fi

  [[ "$count" =~ ^[0-9]+$ ]] || {
    echo "Readiness call count is not numeric for: $pattern ($count)" >&2
    return 1
  }
  [[ "$count" -eq "$expected" ]] || {
    echo "Expected $expected call(s) for: $pattern; found $count" >&2
    return 1
  }
}

# Happy path: both read-only authority checks run in order.
export READINESS_FIXTURE_MODE='success'
"$REAL_BASH" Scripts/verify-production-release-readiness.sh   example/SchneeGlass   >"$FIXTURE/success.log" 2>&1

grep -Fq 'Production release readiness verified:' "$FIXTURE/success.log"
assert_count 1 'Scripts/verify-local-release-source.sh example/SchneeGlass'
assert_count 1 'Scripts/setup-release-governance.sh example/SchneeGlass --verify-only'
assert_count 1 'Scripts/setup-production-release-environment.sh example/SchneeGlass --verify-credential-names'
SOURCE_LINE="$(grep -n 'Scripts/verify-local-release-source.sh' "$LOG" | cut -d: -f1)"
GOV_LINE="$(grep -n 'Scripts/setup-release-governance.sh' "$LOG" | cut -d: -f1)"
ENV_LINE="$(grep -n 'Scripts/setup-production-release-environment.sh' "$LOG" | cut -d: -f1)"
[[ "$SOURCE_LINE" -lt "$GOV_LINE" && "$GOV_LINE" -lt "$ENV_LINE" ]]

# Source proof failure must stop before either authority check.
: > "$LOG"
export READINESS_FIXTURE_MODE='source-failure'
set +e
"$REAL_BASH" Scripts/verify-production-release-readiness.sh \
  example/SchneeGlass \
  >"$FIXTURE/source-failure.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'synthetic source failure' "$FIXTURE/source-failure.log"
assert_count 1 'Scripts/verify-local-release-source.sh example/SchneeGlass'
assert_count 0 'Scripts/setup-release-governance.sh'
assert_count 0 'Scripts/setup-production-release-environment.sh'

# Governance failure must stop before Environment credential-name verification.
: > "$LOG"
export READINESS_FIXTURE_MODE='governance-failure'
set +e
"$REAL_BASH" Scripts/verify-production-release-readiness.sh   example/SchneeGlass   >"$FIXTURE/governance-failure.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'synthetic governance failure' "$FIXTURE/governance-failure.log"
assert_count 1 'Scripts/verify-local-release-source.sh example/SchneeGlass'
assert_count 1 'Scripts/setup-release-governance.sh example/SchneeGlass --verify-only'
assert_count 0 'Scripts/setup-production-release-environment.sh'

# Environment failure must be propagated after governance succeeds.
: > "$LOG"
export READINESS_FIXTURE_MODE='environment-failure'
set +e
"$REAL_BASH" Scripts/verify-production-release-readiness.sh   example/SchneeGlass   >"$FIXTURE/environment-failure.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'synthetic Environment failure' "$FIXTURE/environment-failure.log"
assert_count 1 'Scripts/verify-local-release-source.sh example/SchneeGlass'
assert_count 1 'Scripts/setup-release-governance.sh example/SchneeGlass --verify-only'
assert_count 1 'Scripts/setup-production-release-environment.sh example/SchneeGlass --verify-credential-names'

# Invalid repository identity is rejected before either helper runs.
: > "$LOG"
set +e
"$REAL_BASH" Scripts/verify-production-release-readiness.sh   'invalid repository'   >"$FIXTURE/invalid-repository.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'repository must be owner/repo' "$FIXTURE/invalid-repository.log"
[[ ! -s "$LOG" ]]

rm -rf "$FIXTURE"
echo 'Production release readiness fixtures passed'
