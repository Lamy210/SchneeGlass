#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Release governance setup failed: $*" >&2
  exit 1
}

[[ "$#" -ge 1 && "$#" -le 2 ]] || fail "usage: $0 <owner/repo> [--verify-only]"
REPOSITORY="$1"
MODE="${2:-}"
[[ -z "$MODE" || "$MODE" == '--verify-only' ]] \
  || fail "usage: $0 <owner/repo> [--verify-only]"
VERIFY_ONLY=false
if [[ "$MODE" == '--verify-only' ]]; then
  VERIFY_ONLY=true
fi

[[ "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] \
  || fail "repository must be owner/repo"

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
gh auth status >/dev/null

RULESET_RECIPE='.github/rulesets/main-release-governance.json'
RULESET_NAME='SchneeGlass main release governance'
[[ -f "$RULESET_RECIPE" ]] || fail "ruleset recipe is missing: $RULESET_RECIPE"

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

RULESETS_JSON="$TMP/rulesets.json"
IMMUTABLE_JSON="$TMP/immutable-releases.json"
BRANCH_JSON="$TMP/main-branch.json"
RULES_PAGES_JSON="$TMP/main-rules-pages.json"

gh api "repos/$REPOSITORY/rulesets" > "$RULESETS_JSON"
jq -e 'type == "array"' "$RULESETS_JSON" >/dev/null \
  || fail "repository rulesets response must be a JSON array"

if [[ "$VERIFY_ONLY" != true ]]; then
  if jq -e --arg name "$RULESET_NAME" 'any(.[]; .name == $name)' "$RULESETS_JSON" >/dev/null; then
    fail "matching ruleset already exists: $RULESET_NAME"
  fi

  if [[ "$(jq 'length' "$RULESETS_JSON")" -ne 0 ]]; then
    fail "repository already has rulesets; review existing policy before applying the canonical recipe"
  fi

  gh api \
    --method POST \
    "repos/$REPOSITORY/rulesets" \
    --input "$RULESET_RECIPE" \
    >/dev/null

  gh api \
    --method PUT \
    -H 'X-GitHub-Api-Version: 2026-03-10' \
    "repos/$REPOSITORY/immutable-releases" \
    >/dev/null
fi

gh api \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  "repos/$REPOSITORY/immutable-releases" \
  > "$IMMUTABLE_JSON"
jq -e '.enabled == true' "$IMMUTABLE_JSON" >/dev/null \
  || fail "release immutability is not enabled"

gh api "repos/$REPOSITORY/branches/main" > "$BRANCH_JSON"
jq -e 'type == "object" and (.protected | type == "boolean")' "$BRANCH_JSON" >/dev/null \
  || fail "main branch response is malformed"

gh api --paginate --slurp \
  "repos/$REPOSITORY/rules/branches/main?per_page=100" \
  > "$RULES_PAGES_JSON"
jq -e 'type == "array" and all(.[]; type == "array")' "$RULES_PAGES_JSON" >/dev/null \
  || fail "active branch rules response is malformed"

MAIN_PROTECTED="$(jq -r '.protected' "$BRANCH_JSON")"
bash Scripts/verify-release-branch-protection.sh main "$MAIN_PROTECTED"
bash Scripts/verify-release-required-branch-rules.sh \
  "$RULES_PAGES_JSON" \
  deletion \
  non_fast_forward \
  pull_request
bash Scripts/verify-release-required-checks.sh \
  "$BRANCH_JSON" \
  "$RULES_PAGES_JSON" \
  15368 \
  'Canonical / Xcode 26.6 / App Build / Safety Guards' \
  'Compatibility / macOS 15 / App Build'

if [[ "$VERIFY_ONLY" == true ]]; then
  echo "Release governance verified read-only for $REPOSITORY"
else
  echo "Release governance setup verified for $REPOSITORY"
fi
