#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Production release environment setup failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <owner/repo>"
REPOSITORY="$1"
[[ "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] \
  || fail "repository must be owner/repo"

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
gh auth status >/dev/null

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

BRANCH_JSON="$TMP/main-branch.json"
RULES_PAGES_JSON="$TMP/main-rules-pages.json"

gh api "repos/$REPOSITORY/branches/main" > "$BRANCH_JSON"
jq -e 'type == "object" and (.protected | type == "boolean")' "$BRANCH_JSON" >/dev/null \
  || fail "main branch response is malformed"

MAIN_PROTECTED="$(jq -r '.protected' "$BRANCH_JSON")"
bash Scripts/verify-release-branch-protection.sh main "$MAIN_PROTECTED"

gh api --paginate --slurp \
  "repos/$REPOSITORY/rules/branches/main?per_page=100" \
  > "$RULES_PAGES_JSON"
jq -e 'type == "array" and all(.[]; type == "array")' "$RULES_PAGES_JSON" >/dev/null \
  || fail "active branch rules response is malformed"

bash Scripts/verify-release-required-branch-rules.sh \
  "$RULES_PAGES_JSON" \
  deletion \
  non_fast_forward \
  pull_request
