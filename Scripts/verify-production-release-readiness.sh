#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Production release readiness verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <owner/repo>"
REPOSITORY="$1"
[[ "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]   || fail "repository must be owner/repo"

for helper in   Scripts/setup-release-governance.sh   Scripts/setup-production-release-environment.sh
do
  [[ -f "$helper" ]] || fail "required helper is missing: $helper"
done

bash Scripts/setup-release-governance.sh   "$REPOSITORY"   --verify-only

bash Scripts/setup-production-release-environment.sh   "$REPOSITORY"   --verify-credential-names

echo "Production release readiness verified: governance + Environment credential names for $REPOSITORY"
