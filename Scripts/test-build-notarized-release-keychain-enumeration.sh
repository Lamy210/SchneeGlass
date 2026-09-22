#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-keychain-enumeration-fixture"
rm -rf "$FIXTURE" release-output
mkdir -p "$FIXTURE/bin" "$FIXTURE/runner-temp"
LOG="$FIXTURE/security.log"
OUTPUT="$FIXTURE/output.log"
: > "$LOG"

cleanup() {
  rm -rf "$FIXTURE" release-output
}
trap cleanup EXIT

openssl genpkey \
  -algorithm EC \
  -pkeyopt ec_paramgen_curve:P-256 \
  -out "$FIXTURE/signing.key" >/dev/null 2>&1
openssl req \
  -x509 \
  -new \
  -key "$FIXTURE/signing.key" \
  -out "$FIXTURE/signing.crt" \
  -subj '/CN=SchneeGlass Keychain Enumeration Fixture' \
  -days 1 >/dev/null 2>&1
openssl pkcs12 \
  -export \
  -out "$FIXTURE/DeveloperID.p12" \
  -inkey "$FIXTURE/signing.key" \
  -in "$FIXTURE/signing.crt" \
  -passout pass:fixture-password >/dev/null 2>&1
openssl genpkey \
  -algorithm EC \
  -pkeyopt ec_paramgen_curve:P-256 \
  -out "$FIXTURE/AuthKey.p8" >/dev/null 2>&1

cat > "$FIXTURE/bin/security" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

printf 'security ' >> "${SECURITY_FIXTURE_LOG:?}"
printf '%q ' "$@" >> "$SECURITY_FIXTURE_LOG"
printf '\n' >> "$SECURITY_FIXTURE_LOG"

if [[ "${1:-}" == 'list-keychains' \
  && "${2:-}" == '-d' \
  && "${3:-}" == 'user' \
  && "$#" -eq 3 ]]; then
  echo 'fixture: unable to enumerate original user keychains' >&2
  exit 42
fi

# Any command after enumeration proves the production script continued past
# the failed read. Refuse the side effect while leaving an audit trail.
echo "fixture: unexpected security command after enumeration failure: $*" >&2
exit 43
SHIM
chmod +x "$FIXTURE/bin/security"

export SECURITY_FIXTURE_LOG="$LOG"
export PATH="$FIXTURE/bin:$PATH"
export RUNNER_TEMP="$FIXTURE/runner-temp"
export RELEASE_VERSION='0.1.0'
DEVELOPER_ID_P12_BASE64="$(bash Scripts/encode-release-fixture-base64.sh "$FIXTURE/DeveloperID.p12")"
export DEVELOPER_ID_P12_BASE64
export DEVELOPER_ID_P12_PASSWORD='fixture-password'
export APPLE_TEAM_ID='ABCDE12345'
export APPSTORE_CONNECT_KEY_ID='FGHIJ67890'
export APPSTORE_CONNECT_ISSUER_ID='12345678-1234-1234-1234-1234567890ab'
APPSTORE_CONNECT_PRIVATE_KEY_BASE64="$(bash Scripts/encode-release-fixture-base64.sh "$FIXTURE/AuthKey.p8")"
export APPSTORE_CONNECT_PRIVATE_KEY_BASE64

set +e
bash Scripts/build-notarized-release.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Production release unexpectedly continued after original keychain enumeration failed.' >&2
  exit 1
fi

if ! grep -Fq 'Production release failed: failed to enumerate original user keychains' "$OUTPUT"; then
  cat "$OUTPUT"
  echo 'Production release did not fail at original keychain enumeration.' >&2
  echo 'Observed security commands:' >&2
  cat "$LOG" >&2
  exit 1
fi

if ! grep -Fq 'security list-keychains -d user ' "$LOG"; then
  cat "$LOG" >&2
  echo 'Fixture did not exercise original user keychain enumeration.' >&2
  exit 1
fi

if grep -Fq 'security create-keychain ' "$LOG"; then
  cat "$LOG" >&2
  echo 'Production release attempted to create a keychain after enumeration failed.' >&2
  exit 1
fi

if [[ -e release-output ]]; then
  find release-output -maxdepth 2 -print >&2 || true
  echo 'Production release created release-output after keychain enumeration failed.' >&2
  exit 1
fi

echo 'Original keychain enumeration failure fixture passed'
