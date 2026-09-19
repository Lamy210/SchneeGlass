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

MATCHES="$(grep -RInE 'uses:[[:space:]]+' "$WORKFLOW_DIR" --include='*.yml' --include='*.yaml' || true)"
[[ -n "$MATCHES" ]] || fail "no workflow action references were found"

REMOTE_COUNT=0
FAILURES=0

while IFS= read -r match; do
  [[ -n "$match" ]] || continue

  line="${match#*:*:}"
  if [[ ! "$line" =~ uses:[[:space:]]+([^[:space:]#]+) ]]; then
    echo "Unable to parse action reference: $match" >&2
    FAILURES=$((FAILURES + 1))
    continue
  fi

  spec="${BASH_REMATCH[1]}"
  spec="${spec#\'}"
  spec="${spec%\'}"
  spec="${spec#\"}"
  spec="${spec%\"}"

  case "$spec" in
    ./*|docker://*)
      continue
      ;;
  esac

  REMOTE_COUNT=$((REMOTE_COUNT + 1))

  if [[ ! "$spec" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[^@[:space:]#]+)?@([0-9a-f]{40})$ ]]; then
    echo "Mutable or invalid remote action reference: $match" >&2
    FAILURES=$((FAILURES + 1))
  fi
done <<< "$MATCHES"

[[ "$REMOTE_COUNT" -gt 0 ]] || fail "no remote workflow action references were found"
[[ "$FAILURES" -eq 0 ]] \
  || fail "$FAILURES remote action reference(s) are not pinned to full commit SHAs"

echo "GitHub Actions pins verified: $REMOTE_COUNT remote reference(s) use full commit SHAs"
