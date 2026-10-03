#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${1:-Scripts/build-notarized-release.sh}"

fail() {
  echo "Production release single-instance bundle policy fixture failed: $*" >&2
  exit 1
}

[[ -f "$SCRIPT" ]] || fail "release build script is missing: $SCRIPT"

POLICY_LINE=''
if ! POLICY_LINE="$(grep -nF "'LSMultipleInstancesProhibited'" "$SCRIPT" | cut -d: -f1)"; then
  fail "signed production bundle does not verify LSMultipleInstancesProhibited"
fi
[[ "$POLICY_LINE" =~ ^[1-9][0-9]*$ ]] \
  || fail "single-instance verification must appear exactly once in the production build script"

grep -F '"$APP/Contents/Info.plist"' "$SCRIPT" >/dev/null \
  || fail "single-instance verification must inspect the built app Info.plist"
grep -F "'true'" "$SCRIPT" >/dev/null \
  || fail "single-instance verification must require the exact boolean true value"

NOTARY_LINE=''
if ! NOTARY_LINE="$(grep -nF 'xcrun notarytool submit' "$SCRIPT" | cut -d: -f1)"; then
  fail "notarization submission boundary is missing"
fi
[[ "$NOTARY_LINE" =~ ^[1-9][0-9]*$ ]] \
  || fail "notarization submission boundary must appear exactly once"
(( POLICY_LINE < NOTARY_LINE )) \
  || fail "single-instance bundle verification must run before notarization submission"

echo 'Production release single-instance bundle policy fixture passed'
