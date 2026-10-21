#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

SCRIPT="$ROOT/Scripts/verify-adhoc-publication-candidate.sh"
CANDIDATE_SHA='0123456789abcdef0123456789abcdef01234567'
OTHER_SHA='89abcdef0123456789abcdef0123456789abcdef'
BASE=('Ad-Hoc Release Candidate' '.github/workflows/adhoc-release-candidate.yml' 'workflow_dispatch' 'completed' 'success' 'main' "$CANDIDATE_SHA" '1' "$CANDIDATE_SHA")

bash "$SCRIPT" "${BASE[@]}" >/dev/null

expect_rejection() {
  local label="$1" index="$2" bad="$3" expected="$4"
  local args=("${BASE[@]}")
  args[$index]="$bad"
  local output
  if output="$(bash "$SCRIPT" "${args[@]}" 2>&1)"; then
    printf 'Accepted invalid candidate: %s\n' "$label" >&2
    exit 1
  fi
  if [[ "$output" != *"$expected"* ]]; then
    printf 'Wrong diagnostic for %s: %s\n' "$label" "$output" >&2
    exit 1
  fi
}

expect_rejection 'lookalike workflow' 0 'Ad-Hoc Candidate' 'wrong workflow name'
expect_rejection 'wrong workflow path' 1 '.github/workflows/fake.yml' 'wrong workflow path'
expect_rejection 'PR run' 2 'pull_request' 'candidate must be manually dispatched'
expect_rejection 'queued' 3 'queued' 'candidate run is not completed'
expect_rejection 'failed' 4 'failure' 'candidate run did not succeed'
expect_rejection 'wrong branch' 5 'feature/other' 'candidate run must target main'
expect_rejection 'malformed candidate SHA' 6 'abcdef' 'candidate head SHA is malformed'
expect_rejection 'uppercase candidate SHA' 6 'ABCDEF0123456789abcdef0123456789abcdef01' 'candidate head SHA is malformed'
expect_rejection 'rerun' 7 '2' 'candidate must be a first-attempt workflow run'
expect_rejection 'malformed attempt' 7 'invalid' 'candidate must be a first-attempt workflow run'
expect_rejection 'stale main' 8 "$OTHER_SHA" 'candidate is stale relative to current main'
expect_rejection 'malformed main SHA' 8 'invalid' 'current main SHA is malformed'

if bash "$SCRIPT" "${BASE[@]:0:8}" >/dev/null 2>&1; then
  echo 'Accepted missing current-main SHA' >&2
  exit 1
fi
if bash "$SCRIPT" "${BASE[@]}" 'extra' >/dev/null 2>&1; then
  echo 'Accepted unexpected argument' >&2
  exit 1
fi

echo 'Ad-hoc publication candidate metadata fixtures passed'
