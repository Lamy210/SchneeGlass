#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-developer-id-enumeration-fixture"
rm -rf "$FIXTURE" release-output
mkdir -p "$FIXTURE/bin" "$FIXTURE/runner-temp"
SECURITY_LOG="$FIXTURE/security.log"
XCODEBUILD_LOG="$FIXTURE/xcodebuild.log"
OUTPUT="$FIXTURE/output.log"
: > "$SECURITY_LOG"
: > "$XCODEBUILD_LOG"

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
  -subj '/CN=SchneeGlass Developer ID Enumeration Fixture' \
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

REAL_XCODEBUILD="$(command -v xcodebuild)"

cat > "$FIXTURE/bin/security" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

printf 'security ' >> "${SECURITY_FIXTURE_LOG:?}"
printf '%q ' "$@" >> "$SECURITY_FIXTURE_LOG"
printf '\n' >> "$SECURITY_FIXTURE_LOG"

case "${1:-}" in
  list-keychains)
    if [[ "${2:-}" == '-d' && "${3:-}" == 'user' && "$#" -eq 3 ]]; then
      printf '"%s"\n' '/Users/runner/Library/Keychains/login.keychain-db'
      exit 0
    fi
    if [[ "${2:-}" == '-d' && "${3:-}" == 'user' && "${4:-}" == '-s' ]]; then
      exit 0
    fi
    ;;
  create-keychain|set-keychain-settings|unlock-keychain|import|set-key-partition-list|delete-keychain)
    exit 0
    ;;
  find-identity)
    printf '%s\n' '  1) 0123456789ABCDEF0123456789ABCDEF01234567 "Developer ID Application: SchneeGlass Fixture (ABCDE12345)"'
    echo 'fixture: Developer ID identity enumeration unavailable after partial output' >&2
    exit 42
    ;;
esac

echo "fixture: unexpected security command: $*" >&2
exit 91
SHIM
chmod +x "$FIXTURE/bin/security"

cat > "$FIXTURE/bin/xcodebuild" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

printf 'xcodebuild ' >> "${XCODEBUILD_FIXTURE_LOG:?}"
printf '%q ' "$@" >> "$XCODEBUILD_FIXTURE_LOG"
printf '\n' >> "$XCODEBUILD_FIXTURE_LOG"

for arg in "$@"; do
  if [[ "$arg" == '-showBuildSettings' ]]; then
    exec "${REAL_XCODEBUILD:?}" "$@"
  fi
done

for arg in "$@"; do
  if [[ "$arg" == 'archive' ]]; then
    echo 'fixture: xcodebuild archive reached after identity enumeration failure' >&2
    exit 99
  fi
done

exec "${REAL_XCODEBUILD:?}" "$@"
SHIM
chmod +x "$FIXTURE/bin/xcodebuild"

export SECURITY_FIXTURE_LOG="$SECURITY_LOG"
export XCODEBUILD_FIXTURE_LOG="$XCODEBUILD_LOG"
export REAL_XCODEBUILD
export PATH="$FIXTURE/bin:$PATH"
export RUNNER_TEMP="$FIXTURE/runner-temp"
export RELEASE_VERSION='0.1.0'
export DEVELOPER_ID_P12_BASE64="$(/usr/bin/base64 < "$FIXTURE/DeveloperID.p12" | tr -d '\n')"
export DEVELOPER_ID_P12_PASSWORD='fixture-password'
export APPLE_TEAM_ID='ABCDE12345'
export APPSTORE_CONNECT_KEY_ID='FGHIJ67890'
export APPSTORE_CONNECT_ISSUER_ID='12345678-1234-1234-1234-1234567890ab'
export APPSTORE_CONNECT_PRIVATE_KEY_BASE64="$(/usr/bin/base64 < "$FIXTURE/AuthKey.p8" | tr -d '\n')"

set +e
bash Scripts/build-notarized-release.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Production release unexpectedly succeeded after Developer ID identity enumeration failed.' >&2
  exit 1
fi

if ! grep -Fq 'Production release failed: failed to enumerate Developer ID identities' "$OUTPUT"; then
  cat "$OUTPUT"
  echo 'Production release did not fail closed at Developer ID identity enumeration.' >&2
  echo 'Observed security commands:' >&2
  cat "$SECURITY_LOG" >&2
  echo 'Observed xcodebuild commands:' >&2
  cat "$XCODEBUILD_LOG" >&2
  exit 1
fi

if ! grep -Fq 'security find-identity -v -p codesigning ' "$SECURITY_LOG"; then
  cat "$SECURITY_LOG" >&2
  echo 'Fixture did not exercise Developer ID identity enumeration.' >&2
  exit 1
fi

if grep -Fq ' archive ' "$XCODEBUILD_LOG"; then
  cat "$XCODEBUILD_LOG" >&2
  echo 'Production release reached xcodebuild archive after identity enumeration failed.' >&2
  exit 1
fi

echo 'Developer ID identity enumeration failure fixture passed'
