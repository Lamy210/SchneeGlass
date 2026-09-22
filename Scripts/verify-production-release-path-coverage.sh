#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Production release path coverage validation failed: $*" >&2
  exit 1
}

[[ "$#" -ge 2 ]] || fail "usage: $0 <workflow-path> <required-path> [required-path ...]"

WORKFLOW="$1"
shift

[[ -f "$WORKFLOW" ]] || fail "workflow is missing: $WORKFLOW"

PATHS_SECTION="$(mktemp)"
cleanup() {
  rm -f "$PATHS_SECTION"
}
trap cleanup EXIT

set +e
sed -n '/^  pull_request:/,/^permissions:/p' "$WORKFLOW" > "$PATHS_SECTION"
SED_STATUS=$?
set -e

[[ "$SED_STATUS" -eq 0 ]] \
  || fail "unable to enumerate pull_request.paths (sed status $SED_STATUS)"

for required_path in "$@"; do
  set +e
  grep -Fqx "      - '$required_path'" "$PATHS_SECTION"
  MATCH_STATUS=$?
  set -e

  case "$MATCH_STATUS" in
    0)
      ;;
    1)
      fail "pull_request.paths is missing required path: $required_path"
      ;;
    *)
      fail "unable to probe required path membership: $required_path (grep status $MATCH_STATUS)"
      ;;
  esac
done

echo 'Production release path coverage verified'
