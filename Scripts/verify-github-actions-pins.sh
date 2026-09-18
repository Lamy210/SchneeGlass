#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "GitHub Actions pin verification failed: $*" >&2
  exit 1
}

WORKFLOW_DIR='.github/workflows'
[[ -d "$WORKFLOW_DIR" ]] || fail "workflow directory is missing: $WORKFLOW_DIR"

MATCHES="$(grep -RInE 'uses:[[:space:]]+actions/(checkout|upload-artifact)@' "$WORKFLOW_DIR" --include='*.yml' --include='*.yaml' || true)"
[[ -n "$MATCHES" ]] || fail "no guarded GitHub-owned action references were found"

FAILURES=0
while IFS= read -r match; do
  [[ -n "$match" ]] || continue
  if [[ ! "$match" =~ uses:[[:space:]]+actions/(checkout|upload-artifact)@([0-9a-f]{40})([[:space:]]*#.*)?$ ]]; then
    echo "Mutable or invalid action reference: $match" >&2
    FAILURES=$((FAILURES + 1))
  fi
done <<< "$MATCHES"

[[ "$FAILURES" -eq 0 ]]   || fail "$FAILURES guarded action reference(s) are not pinned to full commit SHAs"

echo 'GitHub Actions pins verified: checkout/upload-artifact use full commit SHAs'
