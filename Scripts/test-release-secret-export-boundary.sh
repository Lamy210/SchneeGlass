#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FAILURES=0
FIXTURE="$(mktemp -d)"
cleanup() {
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

GOOD="$FIXTURE/good.sh"
LATE_CLEAR="$FIXTURE/late-clear.sh"
MISSING_SCOPE="$FIXTURE/missing-scope.sh"

cat > "$GOOD" <<'SH'
SIGNING_DEVELOPER_ID_P12_BASE64="${DEVELOPER_ID_P12_BASE64:-}"
SIGNING_DEVELOPER_ID_P12_PASSWORD="${DEVELOPER_ID_P12_PASSWORD:-}"
SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64="${APPSTORE_CONNECT_PRIVATE_KEY_BASE64:-}"
export -n SIGNING_DEVELOPER_ID_P12_BASE64 SIGNING_DEVELOPER_ID_P12_PASSWORD SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64
unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64
ROOT="$(git rev-parse --show-toplevel)"
DEVELOPER_ID_P12_BASE64="$SIGNING_DEVELOPER_ID_P12_BASE64" \
  DEVELOPER_ID_P12_PASSWORD="$SIGNING_DEVELOPER_ID_P12_PASSWORD" \
  APPSTORE_CONNECT_PRIVATE_KEY_BASE64="$SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64" \
  bash Scripts/verify-release-credential-inputs.sh
cleanup() {
  set +e
  unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64 SIGNING_DEVELOPER_ID_P12_BASE64 SIGNING_DEVELOPER_ID_P12_PASSWORD SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64
  if ((${#ORIGINAL_KEYCHAINS[@]} > 0)); then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1
  fi
}
printf '%s' "$SIGNING_DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D > "$P12_PATH"
printf '%s' "$SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64" | /usr/bin/base64 -D > "$API_KEY_PATH"
unset SIGNING_DEVELOPER_ID_P12_BASE64 SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64
bash Scripts/verify-release-decoded-credentials.sh \
  "$P12_PATH" \
  "$SIGNING_DEVELOPER_ID_P12_PASSWORD" \
  "$API_KEY_PATH"
security import "$P12_PATH" \
  -P "$SIGNING_DEVELOPER_ID_P12_PASSWORD" \
  -T /usr/bin/codesign
unset SIGNING_DEVELOPER_ID_P12_PASSWORD
SH

if ! bash Scripts/verify-release-secret-export-boundary.sh "$GOOD" >"$FIXTURE/good.log" 2>&1; then
  cat "$FIXTURE/good.log"
  echo 'Secret export-boundary validator rejected the valid fixture.' >&2
  FAILURES=$((FAILURES + 1))
fi

awk '
  $0 == "unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64" {
    saved = $0
    next
  }
  $0 == "ROOT=\"$(git rev-parse --show-toplevel)\"" {
    print
    print saved
    next
  }
  { print }
' "$GOOD" > "$LATE_CLEAR"

set +e
bash Scripts/verify-release-secret-export-boundary.sh "$LATE_CLEAR" >"$FIXTURE/late-clear.log" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$FIXTURE/late-clear.log"
  echo 'Secret export-boundary validator unexpectedly accepted clearing after git.' >&2
  FAILURES=$((FAILURES + 1))
elif ! grep -Fq 'exported signing secrets must be cleared before the first git subprocess' "$FIXTURE/late-clear.log"; then
  cat "$FIXTURE/late-clear.log"
  echo 'Late secret clearing did not fail with the expected boundary error.' >&2
  FAILURES=$((FAILURES + 1))
fi

grep -Fv '  APPSTORE_CONNECT_PRIVATE_KEY_BASE64="$SIGNING_APPSTORE_CONNECT_PRIVATE_KEY_BASE64" \' "$GOOD" > "$MISSING_SCOPE"
set +e
bash Scripts/verify-release-secret-export-boundary.sh "$MISSING_SCOPE" >"$FIXTURE/missing-scope.log" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$FIXTURE/missing-scope.log"
  echo 'Secret export-boundary validator unexpectedly accepted missing command-scoped API-key mapping.' >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES release secret export-boundary fixture case(s) failed." >&2
  exit 1
fi

echo 'Release secret export-boundary fixtures passed'
