#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${1:-Scripts/build-adhoc-release-candidate.sh}"

fail() {
  echo "Ad-hoc release single-instance bundle policy fixture failed: $*" >&2
  exit 1
}

[[ -f "$SCRIPT" ]] || fail "ad-hoc release build script is missing: $SCRIPT"
grep -Fq 'INFO_PLIST="$APP/Contents/Info.plist"' "$SCRIPT" \
  || fail "ad-hoc build script must bind INFO_PLIST to the built app bundle"

POLICY_LINE=''
if ! POLICY_LINE="$(grep -nF "'LSMultipleInstancesProhibited'" "$SCRIPT" | cut -d: -f1)"; then
  fail "ad-hoc candidate bundle does not verify LSMultipleInstancesProhibited"
fi
[[ "$POLICY_LINE" =~ ^[1-9][0-9]*$ ]] \
  || fail "single-instance verification must appear exactly once in the ad-hoc build script"

POLICY_START=$((POLICY_LINE - 2))
POLICY_END=$((POLICY_LINE + 2))
(( POLICY_START > 0 )) || fail "single-instance verification block starts unexpectedly early"
POLICY_BLOCK="$(sed -n "${POLICY_START},${POLICY_END}p" "$SCRIPT")"

grep -Fq 'bash Scripts/verify-required-plist-value.sh' <<< "$POLICY_BLOCK" \
  || fail "single-instance verification must use the required plist verifier"
grep -Fq '"$INFO_PLIST"' <<< "$POLICY_BLOCK" \
  || fail "single-instance verification must inspect the built app Info.plist"
grep -Fq "'true'" <<< "$POLICY_BLOCK" \
  || fail "single-instance verification must require the exact boolean true value"

BUILD_LINE=''
if ! BUILD_LINE="$(grep -nF 'xcodebuild \' "$SCRIPT" | cut -d: -f1)"; then
  fail "ad-hoc xcodebuild boundary is missing"
fi
[[ "$BUILD_LINE" =~ ^[1-9][0-9]*$ ]] \
  || fail "ad-hoc xcodebuild boundary must appear exactly once"

PACKAGE_LINE=''
if ! PACKAGE_LINE="$(grep -nF 'ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE_PATH"' "$SCRIPT" | cut -d: -f1)"; then
  fail "ad-hoc archive packaging boundary is missing"
fi
[[ "$PACKAGE_LINE" =~ ^[1-9][0-9]*$ ]] \
  || fail "ad-hoc archive packaging boundary must appear exactly once"

(( BUILD_LINE < POLICY_LINE )) \
  || fail "single-instance bundle verification must run after the ad-hoc app is built"
(( POLICY_LINE < PACKAGE_LINE )) \
  || fail "single-instance bundle verification must run before the ad-hoc candidate is packaged"

echo 'Ad-hoc release single-instance bundle policy fixture passed'
