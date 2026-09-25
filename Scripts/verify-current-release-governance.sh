#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Current release governance verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <owner/repo>"
REPOSITORY="$1"
[[ "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]   || fail "repository must be owner/repo"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

BRANCH_JSON="$TMP/main-branch.json"
RULES_PAGES_JSON="$TMP/main-rules-pages.json"
GITHUB_ACTIONS_APP_ID='15368'
CANONICAL='Canonical / Xcode 26.6 / App Build / Safety Guards'
COMPATIBILITY='Compatibility / macOS 15 / App Build'

gh api "repos/$REPOSITORY/branches/main" > "$BRANCH_JSON"
jq -e 'type == "object" and (.protected | type == "boolean")' "$BRANCH_JSON" >/dev/null   || fail "main branch response is malformed"

MAIN_PROTECTED="$(jq -r '.protected' "$BRANCH_JSON")"
bash Scripts/verify-release-branch-protection.sh main "$MAIN_PROTECTED"

gh api --paginate --slurp   "repos/$REPOSITORY/rules/branches/main?per_page=100"   > "$RULES_PAGES_JSON"
jq -e 'type == "array" and all(.[]; type == "array")' "$RULES_PAGES_JSON" >/dev/null   || fail "active branch rules response is malformed"

bash Scripts/verify-release-required-branch-rules.sh   "$RULES_PAGES_JSON"   deletion   non_fast_forward   pull_request

bash Scripts/verify-release-required-checks.sh   "$BRANCH_JSON"   "$RULES_PAGES_JSON"   "$GITHUB_ACTIONS_APP_ID"   "$CANONICAL"   "$COMPATIBILITY"

echo "Current release governance verified for $REPOSITORY"
