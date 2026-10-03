#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Ad-hoc release candidate build failed: $*" >&2
  exit 1
}

RELEASE_VERSION="${1:-}"
OUTPUT_DIR="${2:-adhoc-release-output}"
DERIVED_DATA="${ADHOC_DERIVED_DATA_PATH:-${RUNNER_TEMP:-/tmp}/SchneeGlassAdhocCandidateDerivedData}"

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "release version must be strict X.Y.Z"

bash Scripts/verify-release-metadata.sh "v$RELEASE_VERSION"

rm -rf "$OUTPUT_DIR" "$DERIVED_DATA"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project SchneeGlass.xcodeproj \
  -scheme SchneeGlass \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

APP="$DERIVED_DATA/Build/Products/Release/SchneeGlass.app"
EXECUTABLE="$APP/Contents/MacOS/SchneeGlass"
INFO_PLIST="$APP/Contents/Info.plist"
SIGNATURE_DETAILS="$OUTPUT_DIR/CODESIGN_DETAILS.txt"
ENTITLEMENTS="$OUTPUT_DIR/ENTITLEMENTS.plist"

[[ -d "$APP" ]] || fail "Release app bundle is missing"
[[ -f "$EXECUTABLE" ]] || fail "Release executable is missing"
plutil -lint "$INFO_PLIST" >/dev/null

codesign \
  --force \
  --deep \
  --sign - \
  --options runtime \
  --entitlements App/SchneeGlass.entitlements \
  "$APP"

bash Scripts/verify-required-plist-value.sh \
  "$INFO_PLIST" \
  'CFBundleIdentifier' \
  'io.github.lamy210.schneeglass' \
  'Ad-hoc release candidate'

bash Scripts/verify-required-plist-value.sh \
  "$INFO_PLIST" \
  'CFBundleShortVersionString' \
  "$RELEASE_VERSION" \
  'Ad-hoc release candidate'

bash Scripts/verify-required-plist-value.sh \
  "$INFO_PLIST" \
  'LSMultipleInstancesProhibited' \
  'true' \
  'Ad-hoc release candidate single-instance policy'

BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] \
  || fail "CFBundleVersion must be a positive integer"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2> "$SIGNATURE_DETAILS"
cat "$SIGNATURE_DETAILS"

bash Scripts/verify-adhoc-signature-details.sh "$SIGNATURE_DETAILS"

codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null
plutil -lint "$ENTITLEMENTS" >/dev/null

bash Scripts/verify-required-plist-value.sh \
  "$ENTITLEMENTS" \
  'com.apple.security.app-sandbox' \
  'true' \
  'Ad-hoc release candidate'

bash Scripts/verify-required-plist-value.sh \
  "$ENTITLEMENTS" \
  'com.apple.security.files.user-selected.read-write' \
  'true' \
  'Ad-hoc release candidate'

bash Scripts/verify-optional-release-entitlements.sh \
  "$ENTITLEMENTS" \
  'Ad-hoc release candidate'

ARCHIVE="SchneeGlass-$RELEASE_VERSION-adhoc-candidate.zip"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE_PATH"

ARCHIVE_SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
[[ "$ARCHIVE_SHA256" =~ ^[0-9a-f]{64}$ ]] || fail "unable to compute archive SHA-256"
printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE" > "$OUTPUT_DIR/SHA256SUMS"
(
  cd "$OUTPUT_DIR"
  shasum -a 256 -c SHA256SUMS
)

ARCH_INFO="$(file "$EXECUTABLE")"
cat > "$OUTPUT_DIR/BUILD_INFO.txt" <<EOF
version=$RELEASE_VERSION
build=$BUILD_NUMBER
source_commit=$GITHUB_SHA
source_branch=$GITHUB_REF_NAME
code_signature=adhoc
apple_developer_id_signed=false
apple_notarized=false
minimum_macos=15.0
executable_info=$ARCH_INFO
distribution=github-adhoc-candidate
EOF

cat > "$OUTPUT_DIR/README.txt" <<EOF
SchneeGlass $RELEASE_VERSION ad-hoc candidate

This artifact is ad-hoc signed for testing only.
It is not signed with an Apple Developer ID certificate and is not notarized by Apple.
Gatekeeper may block first launch.

Verify SHA256SUMS before testing.

Source commit: $GITHUB_SHA
Build: $BUILD_NUMBER
EOF

echo "ADHOC_CANDIDATE_ARCHIVE=$ARCHIVE_PATH"
echo "ADHOC_CANDIDATE_BUILD=$BUILD_NUMBER"
