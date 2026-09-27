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
MISSING_CLEAR="$FIXTURE/missing-clear.sh"
MISSING_CLEANUP_CLEAR="$FIXTURE/missing-cleanup-clear.sh"
EARLY_PASSWORD_CLEAR="$FIXTURE/early-password-clear.sh"

cat > "$GOOD" <<'SH'
cleanup() {
  set +e

  unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64

  if ((${#ORIGINAL_KEYCHAINS[@]} > 0)); then
    security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1
  fi
}
printf '%s' "$DEVELOPER_ID_P12_BASE64" | /usr/bin/base64 -D > "$P12_PATH"
printf '%s' "$APPSTORE_CONNECT_PRIVATE_KEY_BASE64" | /usr/bin/base64 -D > "$API_KEY_PATH"
unset DEVELOPER_ID_P12_BASE64 APPSTORE_CONNECT_PRIVATE_KEY_BASE64
bash Scripts/verify-release-decoded-credentials.sh \
  "$P12_PATH" \
  "$DEVELOPER_ID_P12_PASSWORD" \
  "$API_KEY_PATH"
security import "$P12_PATH" \
  -P "$DEVELOPER_ID_P12_PASSWORD"
unset DEVELOPER_ID_P12_PASSWORD
security set-key-partition-list \
  -S apple-tool:,apple:
SH

if ! bash Scripts/verify-release-secret-environment-lifecycle.sh "$GOOD" >"$FIXTURE/good.log" 2>&1; then
  cat "$FIXTURE/good.log"
  echo 'Secret lifecycle validator rejected the valid ordering fixture.' >&2
  FAILURES=$((FAILURES + 1))
fi

grep -Fv '  unset DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPSTORE_CONNECT_PRIVATE_KEY_BASE64' "$GOOD" > "$MISSING_CLEANUP_CLEAR"
set +e
bash Scripts/verify-release-secret-environment-lifecycle.sh "$MISSING_CLEANUP_CLEAR" >"$FIXTURE/missing-cleanup-clear.log" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$FIXTURE/missing-cleanup-clear.log"
  echo 'Secret lifecycle validator unexpectedly accepted failure cleanup without clearing signing secrets.' >&2
  FAILURES=$((FAILURES + 1))
fi

grep -Fv 'unset DEVELOPER_ID_P12_BASE64 APPSTORE_CONNECT_PRIVATE_KEY_BASE64' "$GOOD" > "$MISSING_CLEAR"
set +e
bash Scripts/verify-release-secret-environment-lifecycle.sh "$MISSING_CLEAR" >"$FIXTURE/missing-clear.log" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$FIXTURE/missing-clear.log"
  echo 'Secret lifecycle validator unexpectedly accepted missing encoded-secret cleanup.' >&2
  FAILURES=$((FAILURES + 1))
fi

awk '
  $0 == "security import \"$P12_PATH\" \\" {
    print "unset DEVELOPER_ID_P12_PASSWORD"
  }
  $0 != "unset DEVELOPER_ID_P12_PASSWORD" {
    print
  }
' "$GOOD" > "$EARLY_PASSWORD_CLEAR"

set +e
bash Scripts/verify-release-secret-environment-lifecycle.sh "$EARLY_PASSWORD_CLEAR" >"$FIXTURE/early-password.log" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$FIXTURE/early-password.log"
  echo 'Secret lifecycle validator unexpectedly accepted password cleanup before security import.' >&2
  FAILURES=$((FAILURES + 1))
elif ! grep -Fq 'PKCS#12 password must remain available through security import' "$FIXTURE/early-password.log"; then
  cat "$FIXTURE/early-password.log"
  echo 'Early password cleanup did not fail with the expected ordering error.' >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES release secret lifecycle fixture case(s) failed." >&2
  exit 1
fi

echo 'Release secret environment lifecycle fixtures passed'
