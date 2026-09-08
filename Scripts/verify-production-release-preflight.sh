#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Production release preflight failed: $*" >&2
  exit 1
}

setting_from() {
  local settings="$1"
  local key="$2"
  printf '%s\n' "$settings" \
    | sed -n "s/^[[:space:]]*${key} = //p" \
    | head -n 1
}

bash Scripts/verify-release-metadata.sh

for tool in codesign security spctl; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is unavailable: $tool"
done

xcrun --find notarytool >/dev/null 2>&1 || fail "xcrun notarytool is unavailable"
xcrun --find stapler >/dev/null 2>&1 || fail "xcrun stapler is unavailable"

RELEASE_SETTINGS="$(xcodebuild \
  -project SchneeGlass.xcodeproj \
  -scheme SchneeGlass \
  -configuration Release \
  -showBuildSettings)"

HARDENED_RUNTIME="$(setting_from "$RELEASE_SETTINGS" ENABLE_HARDENED_RUNTIME)"
ENTITLEMENTS_PATH="$(setting_from "$RELEASE_SETTINGS" CODE_SIGN_ENTITLEMENTS)"
BUNDLE_ID="$(setting_from "$RELEASE_SETTINGS" PRODUCT_BUNDLE_IDENTIFIER)"
DEPLOYMENT_TARGET="$(setting_from "$RELEASE_SETTINGS" MACOSX_DEPLOYMENT_TARGET)"

[[ "$HARDENED_RUNTIME" == "YES" ]] \
  || fail "ENABLE_HARDENED_RUNTIME must be YES for production notarization"
[[ "$ENTITLEMENTS_PATH" == "App/SchneeGlass.entitlements" ]] \
  || fail "unexpected CODE_SIGN_ENTITLEMENTS: $ENTITLEMENTS_PATH"
[[ "$BUNDLE_ID" == "io.github.lamy210.schneeglass" ]] \
  || fail "unexpected bundle identifier: $BUNDLE_ID"
[[ "$DEPLOYMENT_TARGET" == "15.0" ]] \
  || fail "unexpected macOS deployment target: $DEPLOYMENT_TARGET"

[[ -f "$ENTITLEMENTS_PATH" ]] || fail "entitlements file is missing: $ENTITLEMENTS_PATH"
plutil -lint "$ENTITLEMENTS_PATH" >/dev/null

test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$ENTITLEMENTS_PATH")" = 'true' \
  || fail "App Sandbox entitlement must remain enabled"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$ENTITLEMENTS_PATH")" = 'true' \
  || fail "user-selected read-write entitlement must remain enabled"

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$ENTITLEMENTS_PATH" >/dev/null 2>&1; then
  fail "unexpected network client entitlement"
fi

if GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$ENTITLEMENTS_PATH" 2>/dev/null)"; then
  [[ "$GET_TASK_ALLOW" != "true" ]] || fail "get-task-allow must not be enabled for notarized distribution"
fi

echo "Production release preflight OK: Developer ID / Hardened Runtime / Sandbox / notarization toolchain baseline is ready"
