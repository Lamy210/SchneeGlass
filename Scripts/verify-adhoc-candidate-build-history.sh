#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc candidate build-history verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 5 ]] || fail 'usage: verify-adhoc-candidate-build-history.sh <artifact-dir> <expected-version> <expected-build> <expected-source-sha> <trusted-history-dir>'

ARTIFACT_DIR="$1"
VERSION="$2"
BUILD="$3"
SOURCE_SHA="$4"
HISTORY_DIR="$5"

[[ -d "$HISTORY_DIR" && ! -L "$HISTORY_DIR" ]] \
  || fail 'trusted history must be an existing real directory'
[[ "$BUILD" =~ ^[1-9][0-9]{0,8}$ ]] \
  || fail 'candidate build must be a positive decimal with at most 9 digits'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# The candidate is the exact archive whose build metadata is checked. Never
# infer build/version/source identity from an unauthenticated QA text file.
bash "$ROOT/Scripts/verify-adhoc-candidate-artifact.sh" \
  "$ARTIFACT_DIR" "$VERSION" "$BUILD" "$SOURCE_SHA" >/dev/null \
  || fail 'candidate artifact metadata or SHA-256 validation failed'

# The history must have been materialized from a complete authenticated list
# of public Releases. This adapter does not attest to history completeness.
# Reject all symlinks in supplied history, even symlinks ignored by find -type f.
LINKS=''
if ! LINKS="$(find "$HISTORY_DIR" -type l -print -quit)"; then
  fail 'unable to inspect trusted history links'
fi
[[ -z "$LINKS" ]] || fail 'trusted history contains a symlink'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf 'schema_version=1\nbundle_build=%s\n' "$BUILD" > "$TMP/RELEASE_EVIDENCE.txt"

bash "$ROOT/Scripts/verify-release-build-history.sh" \
  "$TMP/RELEASE_EVIDENCE.txt" "$HISTORY_DIR" \
  || fail 'candidate build is not greater than the published build history'

echo "Ad-hoc candidate build-history check passed: version=$VERSION build=$BUILD sha=$SOURCE_SHA"
