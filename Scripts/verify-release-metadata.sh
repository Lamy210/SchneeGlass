#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

PROJECT="SchneeGlass.xcodeproj"
SCHEME="SchneeGlass"
EXPECTED_TAG="${1:-}"

fail() {
  echo "Release metadata validation failed: $*" >&2
  exit 1
}

build_settings() {
  local configuration="$1"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$configuration" \
    -showBuildSettings
}

setting_from() {
  local settings="$1"
  local key="$2"
  printf '%s\n' "$settings" \
    | sed -n "s/^[[:space:]]*${key} = //p" \
    | head -n 1
}

DEBUG_SETTINGS="$(build_settings Debug)"
RELEASE_SETTINGS="$(build_settings Release)"

DEBUG_VERSION="$(setting_from "$DEBUG_SETTINGS" MARKETING_VERSION)"
RELEASE_VERSION="$(setting_from "$RELEASE_SETTINGS" MARKETING_VERSION)"
DEBUG_BUILD="$(setting_from "$DEBUG_SETTINGS" CURRENT_PROJECT_VERSION)"
RELEASE_BUILD="$(setting_from "$RELEASE_SETTINGS" CURRENT_PROJECT_VERSION)"
BUNDLE_ID="$(setting_from "$RELEASE_SETTINGS" PRODUCT_BUNDLE_IDENTIFIER)"

[[ -n "$DEBUG_VERSION" ]] || fail "Debug MARKETING_VERSION is missing"
[[ -n "$RELEASE_VERSION" ]] || fail "Release MARKETING_VERSION is missing"
[[ -n "$DEBUG_BUILD" ]] || fail "Debug CURRENT_PROJECT_VERSION is missing"
[[ -n "$RELEASE_BUILD" ]] || fail "Release CURRENT_PROJECT_VERSION is missing"
[[ -n "$BUNDLE_ID" ]] || fail "Release PRODUCT_BUNDLE_IDENTIFIER is missing"

[[ "$DEBUG_VERSION" == "$RELEASE_VERSION" ]] \
  || fail "Debug/Release MARKETING_VERSION differ: $DEBUG_VERSION vs $RELEASE_VERSION"
[[ "$DEBUG_BUILD" == "$RELEASE_BUILD" ]] \
  || fail "Debug/Release CURRENT_PROJECT_VERSION differ: $DEBUG_BUILD vs $RELEASE_BUILD"

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "MARKETING_VERSION must be strict X.Y.Z SemVer for v0.1 releases: $RELEASE_VERSION"
[[ "$RELEASE_BUILD" =~ ^[1-9][0-9]*$ ]] \
  || fail "CURRENT_PROJECT_VERSION must be a positive integer: $RELEASE_BUILD"
[[ "$BUNDLE_ID" == "io.github.lamy210.schneeglass" ]] \
  || fail "Unexpected bundle identifier: $BUNDLE_ID"

if [[ -n "$EXPECTED_TAG" ]]; then
  [[ "$EXPECTED_TAG" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)$ ]] \
    || fail "Release tag must be vX.Y.Z: $EXPECTED_TAG"
  TAG_VERSION="${BASH_REMATCH[1]}"
  [[ "$TAG_VERSION" == "$RELEASE_VERSION" ]] \
    || fail "Tag $EXPECTED_TAG does not match MARKETING_VERSION $RELEASE_VERSION"
fi

echo "Release metadata OK: version=$RELEASE_VERSION build=$RELEASE_BUILD bundle=$BUNDLE_ID"
