#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Extracted ad-hoc app verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 3 ]] || fail 'usage: verify-extracted-adhoc-app.sh <SchneeGlass.app> <expected-version> <expected-build>'
APP="$1"
VERSION="$2"
BUILD="$3"

[[ "$VERSION" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || fail 'version must be X.Y.Z'
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'build must be positive decimal'
[[ -d "$APP" && ! -L "$APP" ]] || fail 'app must be a real directory, not a symlink'
[[ "$APP" == *.app ]] || fail 'app directory must have a .app suffix'

INFO="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/SchneeGlass"
for item in "$INFO" "$EXECUTABLE"; do
  [[ -f "$item" && ! -L "$item" && -s "$item" ]] \
    || fail "required app member is missing, empty or a symlink: $item"
done

CODESIGN_BIN="${CODESIGN_BIN:-codesign}"
command -v "$CODESIGN_BIN" >/dev/null 2>&1 || fail 'codesign is required'
command -v plutil >/dev/null 2>&1 || fail 'plutil is required'

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/schneeglass-app-verify.XXXXXXXX")" \
  || fail 'unable to create private signature-verification workspace'
trap 'rm -rf -- "$FIXTURE"' EXIT

plutil -lint "$INFO" >/dev/null || fail 'Info.plist is invalid'
bash "$ROOT/Scripts/verify-required-plist-value.sh" \
  "$INFO" CFBundleIdentifier io.github.lamy210.schneeglass 'Downloaded ad-hoc app' \
  || fail 'bundle identifier mismatch'
bash "$ROOT/Scripts/verify-required-plist-value.sh" \
  "$INFO" CFBundleShortVersionString "$VERSION" 'Downloaded ad-hoc app' \
  || fail 'bundle version mismatch'
bash "$ROOT/Scripts/verify-required-plist-value.sh" \
  "$INFO" CFBundleVersion "$BUILD" 'Downloaded ad-hoc app' \
  || fail 'bundle build mismatch'
bash "$ROOT/Scripts/verify-required-plist-value.sh" \
  "$INFO" LSMultipleInstancesProhibited true 'Downloaded ad-hoc app' \
  || fail 'single-instance policy mismatch'

"$CODESIGN_BIN" --verify --deep --strict --verbose=2 "$APP" \
  > "$FIXTURE/verification.txt" 2>&1 || fail 'codesign strict verification failed'
"$CODESIGN_BIN" -dv --verbose=4 "$APP" 2> "$FIXTURE/details.txt" \
  || fail 'unable to read real app signing identity'
bash "$ROOT/Scripts/verify-adhoc-signature-details.sh" \
  "$FIXTURE/details.txt" || fail 'app signature must be ad-hoc with Hardened Runtime'

"$CODESIGN_BIN" -d --entitlements :- "$APP" \
  > "$FIXTURE/entitlements.plist" 2> "$FIXTURE/entitlements.stderr" \
  || fail 'unable to read real app entitlements'
plutil -lint "$FIXTURE/entitlements.plist" >/dev/null || fail 'extracted entitlements are invalid'

bash "$ROOT/Scripts/verify-required-plist-value.sh" \
  "$FIXTURE/entitlements.plist" com.apple.security.app-sandbox true \
  'Downloaded ad-hoc app' || fail 'App Sandbox entitlement missing'
bash "$ROOT/Scripts/verify-required-plist-value.sh" \
  "$FIXTURE/entitlements.plist" com.apple.security.files.user-selected.read-write true \
  'Downloaded ad-hoc app' || fail 'user-selected read-write entitlement missing'

bash "$ROOT/Scripts/verify-optional-release-entitlements.sh" \
  "$FIXTURE/entitlements.plist" 'Downloaded ad-hoc app' \
  || fail 'unexpected optional entitlement'

echo "Real extracted app signature and entitlements verified (NOT Apple notarization): version=$VERSION build=$BUILD"
