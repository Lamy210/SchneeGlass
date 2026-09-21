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

set +e
grep -q '^schema_version=' "$EVIDENCE"
probe_status=$?
set -e

case "$probe_status" in
  0)
    fail "release evidence already contains schema_version"
    ;;
  1)
    ;;
  *)
    fail "unable to probe schema_version (grep status $probe_status)"
    ;;
esac

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
