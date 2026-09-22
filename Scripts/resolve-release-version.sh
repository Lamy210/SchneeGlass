#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Release version resolution failed: $*" >&2
  exit 1
}

SETTINGS=''
XCODEBUILD_STATUS=0
if SETTINGS="$(xcodebuild \
  -project SchneeGlass.xcodeproj \
  -scheme SchneeGlass \
  -configuration Release \
  -showBuildSettings)"; then
  XCODEBUILD_STATUS=0
else
  XCODEBUILD_STATUS=$?
fi

if [[ "$XCODEBUILD_STATUS" -ne 0 ]]; then
  fail "xcodebuild -showBuildSettings exited with status $XCODEBUILD_STATUS"
fi

VERSION=''
EXTRACTION_STATUS=0
set +e
VERSION="$(printf '%s\n' "$SETTINGS" \
  | sed -n 's/^[[:space:]]*MARKETING_VERSION = //p' \
  | head -n 1)"
EXTRACTION_STATUS=$?
set -e

if [[ "$EXTRACTION_STATUS" -ne 0 ]]; then
  fail "MARKETING_VERSION extraction exited with status $EXTRACTION_STATUS"
fi

[[ -n "$VERSION" ]] || fail "MARKETING_VERSION is missing"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "MARKETING_VERSION must be strict X.Y.Z SemVer: $VERSION"

printf '%s\n' "$VERSION"
