#!/usr/bin/env bash
set -eu

fail() {
  echo "Production release path coverage validation failed: $*" >&2
  exit 1
}

[[ "$#" -ge 2 ]] || fail "usage: $0 <workflow-path> <required-path> [required-path ...]"

WORKFLOW="$1"
shift

[[ -f "$WORKFLOW" ]] || fail "workflow is missing: $WORKFLOW"

# Mechanically extracted from the workflow for RED proof.
# The original step did not enable pipefail, so a partial sed result can satisfy grep.
for required_path in "$@"; do
  sed -n '/^  pull_request:/,/^permissions:/p' "$WORKFLOW" \
    | grep -Fq "      - '$required_path'" || {
      fail "pull_request.paths is missing required path: $required_path"
    }
done

echo 'Production release path coverage verified'
