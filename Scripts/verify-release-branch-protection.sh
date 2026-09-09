#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Release branch protection verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 2 ]] || fail "usage: $0 <branch-name> <protected:true|false>"

BRANCH_NAME="$1"
PROTECTED="$2"

[[ "$BRANCH_NAME" == "main" ]] \
  || fail "production release branch must be main, got: $BRANCH_NAME"

case "$PROTECTED" in
  true)
    ;;
  false)
    fail "main is not protected; configure branch protection or a repository ruleset before publication"
    ;;
  *)
    fail "unexpected protected value for main: $PROTECTED"
    ;;
esac

echo "Release branch protection verified: main protected=true"
