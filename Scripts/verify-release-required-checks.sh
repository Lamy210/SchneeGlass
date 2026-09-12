#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release required-check verification failed: $*" >&2
  exit 1
}

[[ "$#" -ge 4 ]] \
  || fail "usage: $0 <branch-json> <rules-pages-json> <required-app-id> <required-check> [required-check ...]"

BRANCH_JSON="$1"
RULES_PAGES_JSON="$2"
REQUIRED_APP_ID="$3"
shift 3

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "$BRANCH_JSON" ]] || fail "branch JSON does not exist: $BRANCH_JSON"
[[ -f "$RULES_PAGES_JSON" ]] || fail "rules JSON does not exist: $RULES_PAGES_JSON"
[[ "$REQUIRED_APP_ID" =~ ^[1-9][0-9]*$ ]] \
  || fail "required app ID must be a positive integer: $REQUIRED_APP_ID"

jq -e 'type == "object"' "$BRANCH_JSON" >/dev/null \
  || fail "branch payload must be a JSON object"
jq -e 'type == "array" and all(.[]; type == "array")' "$RULES_PAGES_JSON" >/dev/null \
  || fail "rules payload must be a slurped array of JSON-array pages"

BOUND_OBSERVED="$(mktemp)"
OTHER_OBSERVED="$(mktemp)"
trap 'rm -f "$BOUND_OBSERVED" "$OTHER_OBSERVED"' EXIT

# A release gate must prove both the exact context and the expected producer. Classic
# `contexts` are deliberately not authority here because they do not expose an explicit app
# binding. Only `checks[]` entries pinned to the expected GitHub App are accepted.
jq -r --argjson expected "$REQUIRED_APP_ID" '
  (.protection.required_status_checks.checks // [])[]?
  | select(.context | type == "string" and length > 0)
  | select(.app_id == $expected)
  | .context
' "$BRANCH_JSON" >> "$BOUND_OBSERVED"

jq -r --argjson expected "$REQUIRED_APP_ID" '
  (
    (.protection.required_status_checks.contexts // [])[]?
    | select(type == "string" and length > 0)
    | . + " [classic context without explicit app binding]"
  ),
  (
    (.protection.required_status_checks.checks // [])[]?
    | select(.context | type == "string" and length > 0)
    | select(.app_id != $expected)
    | .context + " [classic app_id=" + ((.app_id // "null") | tostring) + "]"
  )
' "$BRANCH_JSON" >> "$OTHER_OBSERVED"

# The active branch-rules endpoint returns only rules that currently apply. Ruleset checks are
# accepted only when `integration_id` explicitly pins them to the expected GitHub App.
jq -r --argjson expected "$REQUIRED_APP_ID" '
  .[][]
  | select(.type == "required_status_checks")
  | (.parameters.required_status_checks // [])[]?
  | select(.context | type == "string" and length > 0)
  | select(.integration_id == $expected)
  | .context
' "$RULES_PAGES_JSON" >> "$BOUND_OBSERVED"

jq -r --argjson expected "$REQUIRED_APP_ID" '
  .[][]
  | select(.type == "required_status_checks")
  | (.parameters.required_status_checks // [])[]?
  | select(.context | type == "string" and length > 0)
  | select(.integration_id != $expected)
  | .context + " [ruleset integration_id=" + ((.integration_id // "null") | tostring) + "]"
' "$RULES_PAGES_JSON" >> "$OTHER_OBSERVED"

sort -u -o "$BOUND_OBSERVED" "$BOUND_OBSERVED"
sort -u -o "$OTHER_OBSERVED" "$OTHER_OBSERVED"

for required_check in "$@"; do
  [[ -n "$required_check" ]] || fail "required check name must not be empty"
  if ! grep -Fqx -- "$required_check" "$BOUND_OBSERVED"; then
    echo "Observed checks bound to app ID $REQUIRED_APP_ID:" >&2
    if [[ -s "$BOUND_OBSERVED" ]]; then
      sed 's/^/  - /' "$BOUND_OBSERVED" >&2
    else
      echo "  (none)" >&2
    fi
    if [[ -s "$OTHER_OBSERVED" ]]; then
      echo "Observed unbound or other-source checks (not accepted):" >&2
      sed 's/^/  - /' "$OTHER_OBSERVED" >&2
    fi
    fail "missing required status check from app ID $REQUIRED_APP_ID: $required_check"
  fi
done

echo "Release required checks verified for app ID $REQUIRED_APP_ID: $*"
