#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Local release source verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <owner/repo>"
REPOSITORY="$1"
[[ "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] \
  || fail "repository must be owner/repo"

GIT_BIN="${GIT_BIN:-git}"
GH_BIN="${GH_BIN:-gh}"
JQ_BIN="${JQ_BIN:-jq}"

command -v "$GIT_BIN" >/dev/null 2>&1 || fail "git command is unavailable"
command -v "$GH_BIN" >/dev/null 2>&1 || fail "gh command is unavailable"
command -v "$JQ_BIN" >/dev/null 2>&1 || fail "jq command is unavailable"

"$GH_BIN" auth status >/dev/null

capture_git() {
  local label="$1"
  shift
  local output=''
  local status=0

  set +e
  output="$("$GIT_BIN" "$@")"
  status=$?
  set -e

  [[ "$status" -eq 0 ]] || fail "$label failed (git status $status)"
  printf '%s' "$output"
}

ROOT="$(capture_git 'repository root probe' rev-parse --show-toplevel)"
[[ -n "$ROOT" && -d "$ROOT" ]] || fail "repository root is invalid"
cd "$ROOT"

BRANCH="$(capture_git 'current branch probe' branch --show-current)"
[[ "$BRANCH" == 'main' ]] || fail "current branch must be main (found: ${BRANCH:-detached})"

LOCAL_SHA="$(capture_git 'local HEAD probe' rev-parse HEAD)"
[[ "$LOCAL_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "local HEAD must be a lowercase 40-hex commit"

WORKTREE_STATUS="$(capture_git 'working tree probe' status --porcelain=v1 --untracked-files=normal)"
[[ -z "$WORKTREE_STATUS" ]] || fail "working tree must be clean"

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

BRANCH_JSON="$TMP/main-branch.json"
"$GH_BIN" api "repos/$REPOSITORY/branches/main" > "$BRANCH_JSON"

"$JQ_BIN" -e '
  type == "object" and
  .name == "main" and
  (.commit | type == "object") and
  (.commit.sha | type == "string" and test("^[0-9a-f]{40}$"))
' "$BRANCH_JSON" >/dev/null \
  || fail "remote main branch response is malformed"

REMOTE_SHA="$("$JQ_BIN" -r '.commit.sha' "$BRANCH_JSON")"
[[ "$REMOTE_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "remote main SHA must be a lowercase 40-hex commit"

[[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] \
  || fail "local HEAD does not match live remote main"

echo "Local release source verified: branch=main sha=$LOCAL_SHA clean=true"
