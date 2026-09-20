#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Release evidence schema initialization failed: $*" >&2
  exit 1
}

EVIDENCE="${1:-$ROOT/release-output/RELEASE_EVIDENCE.txt}"
[[ -f "$EVIDENCE" ]] || fail "release evidence is missing: $EVIDENCE"

# Mechanically extracted from the production workflow for TDD.
# The RED fixture demonstrates that this does not distinguish a failed probe
# from confirmed absence and does not reliably reject a duplicate schema key.
! grep -q '^schema_version=' "$EVIDENCE"

TEMP="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/SchneeGlass-RELEASE_EVIDENCE.$$"
cleanup() {
  rm -f "$TEMP"
}
trap cleanup EXIT

{
  echo 'schema_version=1'
  cat "$EVIDENCE"
} > "$TEMP"
mv "$TEMP" "$EVIDENCE"

trap - EXIT
echo "Release evidence schema initialized: $EVIDENCE"
