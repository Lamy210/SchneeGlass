#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release branch-rule verification failed: $*" >&2
  exit 1
}

[[ "$#" -ge 2 ]] \
  || fail "usage: $0 <rules-pages-json> <required-rule-type> [required-rule-type ...]"

RULES_PAGES_JSON="$1"
shift

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "$RULES_PAGES_JSON" ]] || fail "rules JSON does not exist: $RULES_PAGES_JSON"

jq -e 'type == "array" and all(.[]; type == "array")' "$RULES_PAGES_JSON" >/dev/null \
  || fail "rules payload must be a slurped array of JSON-array pages"

OBSERVED="$(mktemp)"
trap 'rm -f "$OBSERVED"' EXIT

# `GET /repos/{owner}/{repo}/rules/branches/{branch}` returns only active rules that
# currently apply to the branch. Presence in this payload is therefore release authority
# for rule type enforcement, while bypass-list review remains a separate human attestation.
jq -r '
  .[][]
  | .type
  | select(type == "string" and length > 0)
' "$RULES_PAGES_JSON" \
  | sort -u > "$OBSERVED"

for required_rule in "$@"; do
  [[ -n "$required_rule" ]] || fail "required rule type must not be empty"
  if ! grep -Fqx -- "$required_rule" "$OBSERVED"; then
    echo 'Observed active branch rule types:' >&2
    if [[ -s "$OBSERVED" ]]; then
      sed 's/^/  - /' "$OBSERVED" >&2
    else
      echo '  (none)' >&2
    fi
    fail "missing required active branch rule: $required_rule"
  fi
done

echo "Release branch rules verified: $*"
