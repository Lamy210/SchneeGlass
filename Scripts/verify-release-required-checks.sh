#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release required-check verification failed: $*" >&2
  exit 1
}

[[ "$#" -ge 3 ]] || fail "usage: $0 <branch-json> <rules-pages-json> <required-check> [required-check ...]"

BRANCH_JSON="$1"
RULES_PAGES_JSON="$2"
shift 2

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "$BRANCH_JSON" ]] || fail "branch JSON does not exist: $BRANCH_JSON"
[[ -f "$RULES_PAGES_JSON" ]] || fail "rules JSON does not exist: $RULES_PAGES_JSON"

jq -e 'type == "object"' "$BRANCH_JSON" >/dev/null \
  || fail "branch payload must be a JSON object"
jq -e 'type == "array" and all(.[]; type == "array")' "$RULES_PAGES_JSON" >/dev/null \
  || fail "rules payload must be a slurped array of JSON-array pages"

OBSERVED="$(mktemp)"
trap 'rm -f "$OBSERVED"' EXIT

# Classic branch-protection status checks are exposed on the branch summary. Support both
# historical `contexts` and the more specific `checks[].context` representation.
jq -r '
  (
    (.protection.required_status_checks.contexts // [])[]?,
    (.protection.required_status_checks.checks // [])[]?.context
  )
  | select(type == "string" and length > 0)
' "$BRANCH_JSON" >> "$OBSERVED"

# Rulesets are readable with repository Metadata permission. `gh api --paginate --slurp`
# stores each REST page as one element in the outer array, so flatten those pages before
# collecting active required-status-check rule contexts.
jq -r '
  .[][]
  | select(.type == "required_status_checks")
  | (.parameters.required_status_checks // [])[]?.context
  | select(type == "string" and length > 0)
' "$RULES_PAGES_JSON" >> "$OBSERVED"

sort -u -o "$OBSERVED" "$OBSERVED"

for required_check in "$@"; do
  [[ -n "$required_check" ]] || fail "required check name must not be empty"
  if ! grep -Fqx -- "$required_check" "$OBSERVED"; then
    echo "Observed required checks:" >&2
    if [[ -s "$OBSERVED" ]]; then
      sed 's/^/  - /' "$OBSERVED" >&2
    else
      echo "  (none)" >&2
    fi
    fail "missing required status check: $required_check"
  fi
done

echo "Release required checks verified: $*"
