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

GOOD="$FIXTURE/good.yml"
JOB_SCOPE="$FIXTURE/job-scope.yml"
MISSING="$FIXTURE/missing.yml"

cat > "$GOOD" <<'YAML'
name: fixture
jobs:
  sign-notarize:
    env:
      DEVELOPER_DIR: /Applications/Xcode.app/Contents/Developer
      RELEASE_VERSION: 0.1.0
    steps:
      - name: Checkout
        run: true
      - name: Build signed and notarized release candidate
        env:
          DEVELOPER_ID_P12_BASE64: ${{ secrets.DEVELOPER_ID_P12_BASE64 }}
          DEVELOPER_ID_P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
          APPSTORE_CONNECT_PRIVATE_KEY_BASE64: ${{ secrets.APPSTORE_CONNECT_PRIVATE_KEY_BASE64 }}
          APPLE_TEAM_ID: ${{ vars.APPLE_TEAM_ID }}
          APPSTORE_CONNECT_KEY_ID: ${{ vars.APPSTORE_CONNECT_KEY_ID }}
          APPSTORE_CONNECT_ISSUER_ID: ${{ vars.APPSTORE_CONNECT_ISSUER_ID }}
        run: true
      - name: Evidence
        run: true
YAML

if ! bash Scripts/verify-production-release-secret-scope.sh "$GOOD" >"$FIXTURE/good.log" 2>&1; then
  cat "$FIXTURE/good.log"
  echo 'Credential-scope validator rejected the valid step-scoped fixture.' >&2
  FAILURES=$((FAILURES + 1))
fi

cat > "$JOB_SCOPE" <<'YAML'
name: fixture
jobs:
  sign-notarize:
    env:
      DEVELOPER_DIR: /Applications/Xcode.app/Contents/Developer
      RELEASE_VERSION: 0.1.0
      DEVELOPER_ID_P12_BASE64: ${{ secrets.DEVELOPER_ID_P12_BASE64 }}
    steps:
      - name: Checkout
        run: true
      - name: Build signed and notarized release candidate
        env:
          DEVELOPER_ID_P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
          APPSTORE_CONNECT_PRIVATE_KEY_BASE64: ${{ secrets.APPSTORE_CONNECT_PRIVATE_KEY_BASE64 }}
          APPLE_TEAM_ID: ${{ vars.APPLE_TEAM_ID }}
          APPSTORE_CONNECT_KEY_ID: ${{ vars.APPSTORE_CONNECT_KEY_ID }}
          APPSTORE_CONNECT_ISSUER_ID: ${{ vars.APPSTORE_CONNECT_ISSUER_ID }}
        run: true
      - name: Evidence
        run: true
YAML

set +e
bash Scripts/verify-production-release-secret-scope.sh "$JOB_SCOPE" >"$FIXTURE/job-scope.log" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$FIXTURE/job-scope.log"
  echo 'Credential-scope validator unexpectedly accepted a job-scoped signing secret.' >&2
  FAILURES=$((FAILURES + 1))
elif ! grep -Fq 'DEVELOPER_ID_P12_BASE64 must not be exposed at sign-notarize job scope' "$FIXTURE/job-scope.log"; then
  cat "$FIXTURE/job-scope.log"
  echo 'Job-scope leak did not fail with the expected policy error.' >&2
  FAILURES=$((FAILURES + 1))
fi

grep -Fv 'APPSTORE_CONNECT_PRIVATE_KEY_BASE64:' "$GOOD" > "$MISSING"
set +e
bash Scripts/verify-production-release-secret-scope.sh "$MISSING" >"$FIXTURE/missing.log" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$FIXTURE/missing.log"
  echo 'Credential-scope validator unexpectedly accepted a missing signing secret.' >&2
  FAILURES=$((FAILURES + 1))
elif ! grep -Fq 'APPSTORE_CONNECT_PRIVATE_KEY_BASE64 must be referenced exactly once in the workflow' "$FIXTURE/missing.log"; then
  cat "$FIXTURE/missing.log"
  echo 'Missing signing secret did not fail with the expected policy error.' >&2
  FAILURES=$((FAILURES + 1))
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES production release secret-scope fixture case(s) failed." >&2
  exit 1
fi

echo 'Production release secret-scope fixtures passed'
