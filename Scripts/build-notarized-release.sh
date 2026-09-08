#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Production release failed: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "required release environment value is missing: $name"
}

for name in \
  RELEASE_VERSION \
  DEVELOPER_ID_P12_BASE64 \
  DEVELOPER_ID_P12_PASSWORD \
  APPLE_TEAM_ID \
  APPSTORE_CONNECT_KEY_ID \
  APPSTORE_CONNECT_ISSUER_ID \
  APPSTORE_CONNECT_PRIVATE_KEY_BASE64; do
  require_env "$name"
done

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "RELEASE_VERSION must be X.Y.Z"

bash Scripts/verify-release-metadata.sh "v${RELEASE_VERSION}"
bash Scripts/verify-production-release-preflight.sh

RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
OUTPUT_DIR="${RELEASE_OUTPUT_DIR:-$ROOT/release-output}"
KEYCHAIN_PATH="$RUNNER_TEMP/SchneeGlassRelease.keychain-db"
P12_PATH="$RUNNER_TEMP/DeveloperID.p12"
API_KEY_PATH="$RUNNER_TEMP/AuthKey.p8"
ARCHIVE_PATH="$RUNNER_TEMP/SchneeGlass.xcarchive"
NOTARY_ZIP="$RUNNER_TEMP/SchneeGlass-${RELEASE_VERSION}-notarization.zip"
NOTARY_RESULT="$RUNNER_TEMP/notary-result.json"
NOTARY_LOG="$RUNNER_TEMP/notary-log.json"
SIGNED_ENTITLEMENTS="$RUNNER_TEMP/signed-entitlements.plist"
CODESIGN_DETAILS="$RUNNER_TEMP/codesign-details.txt"
KEYCHAIN_PASSWORD="$(openssl rand -hex 32)"

ORIGINAL_KEYCHAINS=()
while IFS= read -r keychain; do
  keychain="${keychain#\"}"
  keychain="${keychain%\"}"
  [[ -n "$keychain" ]] && ORIGINAL_KEYCHAINS+=("$keychain")
done < <(security list-keychains -d user)

cleanup() {
  set +e

  if ((${#ORIGINAL_KEYCHAINS[@]} > 0)); then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1
  fi

  security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1
  rm -f \
    "$P12_PATH" \
    "$API_KEY_PATH" \
    "$NOTARY_ZIP" \
    "$NOTARY_RESULT" \
    "$NOTARY_LOG" \
    "$SIGNED_ENTITLEMENTS" \
    "$CODESIGN_DETAILS"
}
trap cleanup EXIT

rm -rf "$ARCHIVE_PATH" "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/evidence"

printf '%s' "$DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D > "$P12_PATH"
printf '%s' "$APPSTORE_CONNECT_PRIVATE_KEY_BASE64" | /usr/bin/base64 -D > "$API_KEY_PATH"
chmod 600 "$P12_PATH" "$API_KEY_PATH"

security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$P12_PATH" \
  -k "$KEYCHAIN_PATH" \
  -P "$DEVELOPER_ID_P12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security >/dev/null
security set-key-partition-list \
  -S apple-tool:,apple: \
  -s \
  -k "$KEYCHAIN_PASSWORD" \
  "$KEYCHAIN_PATH" >/dev/null

security list-keychains -d user -s "$KEYCHAIN_PATH" "${ORIGINAL_KEYCHAINS[@]}"

IDENTITY_LINES="$(security find-identity -v -p codesigning "$KEYCHAIN_PATH" \
  | grep '"Developer ID Application:' || true)"
IDENTITY_COUNT="$(printf '%s\n' "$IDENTITY_LINES" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"

[[ "$IDENTITY_COUNT" == "1" ]] \
  || fail "expected exactly one Developer ID Application identity in temporary keychain; found $IDENTITY_COUNT"
printf '%s\n' "$IDENTITY_LINES" | grep -F "($APPLE_TEAM_ID)" >/dev/null \
  || fail "Developer ID identity does not match APPLE_TEAM_ID"

IDENTITY_HASH="$(printf '%s\n' "$IDENTITY_LINES" | awk '{print $2}')"
[[ -n "$IDENTITY_HASH" ]] || fail "unable to resolve Developer ID identity hash"

xcodebuild archive \
  -project SchneeGlass.xcodeproj \
  -scheme SchneeGlass \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY_HASH" \
  OTHER_CODE_SIGN_FLAGS="--keychain $KEYCHAIN_PATH" \
  archive

APP="$ARCHIVE_PATH/Products/Applications/SchneeGlass.app"
[[ -d "$APP" ]] || fail "signed archive app is missing"

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2> "$CODESIGN_DETAILS"

cat "$CODESIGN_DETAILS"
grep -F 'Authority=Developer ID Application:' "$CODESIGN_DETAILS" >/dev/null \
  || fail "signed app is not using Developer ID Application authority"
grep -F "TeamIdentifier=$APPLE_TEAM_ID" "$CODESIGN_DETAILS" >/dev/null \
  || fail "signed app TeamIdentifier mismatch"
grep -E '^flags=.*runtime' "$CODESIGN_DETAILS" >/dev/null \
  || fail "Hardened Runtime flag is missing from signed app"
grep -E '^Timestamp=' "$CODESIGN_DETAILS" >/dev/null \
  || fail "secure signing timestamp is missing"

codesign -d --entitlements :- "$APP" > "$SIGNED_ENTITLEMENTS" 2>/dev/null
plutil -lint "$SIGNED_ENTITLEMENTS" >/dev/null

test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$SIGNED_ENTITLEMENTS")" = 'true' \
  || fail "signed app lost App Sandbox entitlement"
test "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.files.user-selected.read-write' "$SIGNED_ENTITLEMENTS")" = 'true' \
  || fail "signed app lost user-selected read-write entitlement"

if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.network.client' "$SIGNED_ENTITLEMENTS" >/dev/null 2>&1; then
  fail "signed app unexpectedly gained network client entitlement"
fi

if GET_TASK_ALLOW="$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$SIGNED_ENTITLEMENTS" 2>/dev/null)"; then
  [[ "$GET_TASK_ALLOW" != "true" ]] || fail "signed app has get-task-allow enabled"
fi

cp "$SIGNED_ENTITLEMENTS" "$OUTPUT_DIR/evidence/signed-entitlements.plist"
cp "$CODESIGN_DETAILS" "$OUTPUT_DIR/evidence/codesign-details.txt"

ditto -c -k --sequesterRsrc --keepParent "$APP" "$NOTARY_ZIP"

xcrun notarytool submit "$NOTARY_ZIP" \
  --key "$API_KEY_PATH" \
  --key-id "$APPSTORE_CONNECT_KEY_ID" \
  --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
  --wait \
  --output-format json > "$NOTARY_RESULT"

NOTARY_STATUS="$(plutil -extract status raw -o - "$NOTARY_RESULT")"
NOTARY_ID="$(plutil -extract id raw -o - "$NOTARY_RESULT")"
[[ -n "$NOTARY_ID" ]] || fail "notarytool did not return a submission id"

if [[ "$NOTARY_STATUS" != "Accepted" ]]; then
  xcrun notarytool log "$NOTARY_ID" \
    --key "$API_KEY_PATH" \
    --key-id "$APPSTORE_CONNECT_KEY_ID" \
    --issuer "$APPSTORE_CONNECT_ISSUER_ID" \
    "$NOTARY_LOG" || true

  if [[ -f "$NOTARY_LOG" ]]; then
    cp "$NOTARY_LOG" "$OUTPUT_DIR/evidence/notary-log.json"
    cat "$NOTARY_LOG"
  fi

  fail "Apple notarization did not return Accepted: $NOTARY_STATUS"
fi

cp "$NOTARY_RESULT" "$OUTPUT_DIR/evidence/notary-result.json"

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

FINAL_ARCHIVE="SchneeGlass-${RELEASE_VERSION}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT_DIR/$FINAL_ARCHIVE"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$FINAL_ARCHIVE" > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)

cat > "$OUTPUT_DIR/RELEASE_EVIDENCE.txt" <<EOF
version=$RELEASE_VERSION
notarization_id=$NOTARY_ID
notarization_status=$NOTARY_STATUS
codesign=verified
stapler=validated
gatekeeper=accepted
EOF

echo "Production release artifact ready for manual QA: $OUTPUT_DIR/$FINAL_ARCHIVE"
