#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Release bundle metadata validation failed: $*" >&2
  exit 1
}

VERSION="${1:-}"
ARCHIVE="${2:-}"
EVIDENCE="${3:-}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "version must be strict X.Y.Z"

if [[ -z "$ARCHIVE" ]]; then
  ARCHIVE="$ROOT/release-output/SchneeGlass-${VERSION}.zip"
fi
if [[ -z "$EVIDENCE" ]]; then
  EVIDENCE="$ROOT/release-output/RELEASE_EVIDENCE.txt"
fi

[[ -f "$ARCHIVE" ]] || fail "release archive is missing: $ARCHIVE"
[[ -f "$EVIDENCE" ]] || fail "release evidence is missing: $EVIDENCE"

command -v ditto >/dev/null 2>&1 || fail "ditto is required"
command -v plutil >/dev/null 2>&1 || fail "plutil is required"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SchneeGlassBundleMetadata.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

ditto -x -k "$ARCHIVE" "$WORK_DIR"

APP="$WORK_DIR/SchneeGlass.app"
INFO_PLIST="$APP/Contents/Info.plist"

[[ -d "$APP" ]] || fail "release archive does not contain SchneeGlass.app at its root"
[[ -f "$INFO_PLIST" ]] || fail "signed app Info.plist is missing"
plutil -lint "$INFO_PLIST" >/dev/null

BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$INFO_PLIST")"
BUNDLE_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
BUNDLE_BUILD="$(plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"

[[ "$BUNDLE_ID" == "io.github.lamy210.schneeglass" ]] \
  || fail "unexpected bundle identifier: $BUNDLE_ID"
[[ "$BUNDLE_VERSION" == "$VERSION" ]] \
  || fail "signed bundle version $BUNDLE_VERSION does not match requested version $VERSION"
[[ "$BUNDLE_BUILD" =~ ^[1-9][0-9]*$ ]] \
  || fail "signed bundle build must be a positive integer: $BUNDLE_BUILD"

for key in bundle_identifier bundle_version bundle_build; do
  if grep -q "^${key}=" "$EVIDENCE"; then
    fail "release evidence already contains $key"
  fi
done

cat >> "$EVIDENCE" <<EOF
bundle_identifier=$BUNDLE_ID
bundle_version=$BUNDLE_VERSION
bundle_build=$BUNDLE_BUILD
EOF

trap - EXIT
rm -rf "$WORK_DIR"

echo "Signed bundle metadata recorded: bundle=$BUNDLE_ID version=$BUNDLE_VERSION build=$BUNDLE_BUILD"
