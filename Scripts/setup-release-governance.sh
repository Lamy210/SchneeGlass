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
RULESET_CREATE_JSON="$TMP/ruleset-create.json"
RULESET_DETAIL_JSON="$TMP/canonical-ruleset.json"
IMMUTABLE_JSON="$TMP/immutable-releases.json"
BRANCH_JSON="$TMP/main-branch.json"
RULES_PAGES_JSON="$TMP/main-rules-pages.json"

gh api "repos/$REPOSITORY/rulesets" > "$RULESETS_JSON"
jq -e 'type == "array"' "$RULESETS_JSON" >/dev/null \
  || fail "repository rulesets response must be a JSON array"

RULESET_COUNT=''
set +e
RULESET_COUNT="$(jq 'length' "$RULESETS_JSON")"
RULESET_COUNT_STATUS=$?
set -e

[[ "$RULESET_COUNT_STATUS" -eq 0 ]] \
  || fail "unable to enumerate repository ruleset count (jq status $RULESET_COUNT_STATUS)"
[[ "$RULESET_COUNT" =~ ^[0-9]+$ ]] \
  || fail "repository ruleset count is not numeric: $RULESET_COUNT"

RULESET_ID=''

if [[ "$VERIFY_ONLY" == true ]]; then
  jq -e --arg name "$RULESET_NAME" 'any(.[]; .name == $name)' "$RULESETS_JSON" >/dev/null \
    || fail "verify-only requires canonical ruleset: $RULESET_NAME"
  [[ "$RULESET_COUNT" -eq 1 ]] \
    || fail "verify-only requires canonical ruleset to be the only repository ruleset"
  jq -e '.[0].enforcement == "active"' "$RULESETS_JSON" >/dev/null \
    || fail "verify-only requires canonical ruleset enforcement=active"
  RULESET_ID="$(jq -r --arg name "$RULESET_NAME" '.[] | select(.name == $name) | .id // empty' "$RULESETS_JSON")"
else
  CANONICAL_RULESET_COUNT="$(jq --arg name "$RULESET_NAME" '[.[] | select(.name == $name)] | length' "$RULESETS_JSON")"

  if [[ "$CANONICAL_RULESET_COUNT" -eq 1 && "$RULESET_COUNT" -eq 1 ]]; then
    jq -e '.[0].enforcement == "active"' "$RULESETS_JSON" >/dev/null \
      || fail "matching ruleset exists but enforcement is not active: $RULESET_NAME"
    RULESET_ID="$(jq -r --arg name "$RULESET_NAME" '.[] | select(.name == $name) | .id // empty' "$RULESETS_JSON")"
  else
    if [[ "$CANONICAL_RULESET_COUNT" -ne 0 ]]; then
      fail "matching ruleset already exists: $RULESET_NAME"
    fi

    if [[ "$RULESET_COUNT" -ne 0 ]]; then
      fail "repository already has rulesets; review existing policy before applying the canonical recipe"
    fi

    gh api \
      --method POST \
      "repos/$REPOSITORY/rulesets" \
      --input "$RULESET_RECIPE" \
      > "$RULESET_CREATE_JSON"
    RULESET_ID="$(jq -r '.id // empty' "$RULESET_CREATE_JSON")"
  fi
fi

[[ "$RULESET_ID" =~ ^[1-9][0-9]*$ ]] \
  || fail "canonical ruleset ID must be a positive integer"

gh api \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  "repos/$REPOSITORY/rulesets/$RULESET_ID" \
  > "$RULESET_DETAIL_JSON"

jq -e \
  --arg name "$RULESET_NAME" \
  'type == "object" and
   .name == $name and
   .target == "branch" and
   .enforcement == "active" and
   .conditions.ref_name.include == ["refs/heads/main"] and
   .conditions.ref_name.exclude == []' \
  "$RULESET_DETAIL_JSON" >/dev/null \
  || fail "canonical ruleset detail does not match the release governance baseline"

jq -e 'has("bypass_actors") and (.bypass_actors | type == "array")' \
  "$RULESET_DETAIL_JSON" >/dev/null \
  || fail "canonical ruleset bypass actors are not observable; authenticate with ruleset write access"

jq -e '.bypass_actors | length == 0' "$RULESET_DETAIL_JSON" >/dev/null \
  || fail "canonical ruleset must not define bypass actors"

bash Scripts/verify-release-canonical-ruleset.sh \
  "$RULESET_RECIPE" \
  "$RULESET_DETAIL_JSON"

if [[ "$VERIFY_ONLY" != true ]]; then
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
