#!/usr/bin/env bash
set -eu

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Release version resolution failed: $*" >&2
  exit 1
}

SETTINGS="$(xcodebuild \
  -project SchneeGlass.xcodeproj \
  -scheme SchneeGlass \
  -configuration Release \
  -showBuildSettings)"

VERSION="$(printf '%s\n' "$SETTINGS" \
  | sed -n 's/^[[:space:]]*MARKETING_VERSION = //p' \
  | head -n 1)"

[[ -n "$VERSION" ]] || fail "MARKETING_VERSION is missing"
printf '%s\n' "$VERSION"
