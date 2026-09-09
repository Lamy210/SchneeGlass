#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Release evidence validation failed: $*" >&2
  exit 1
}

EVIDENCE="${1:-}"
EXPECTED_VERSION="${2:-}"
EXPECTED_COMMIT="${3:-}"

[[ -n "$EVIDENCE" ]] || fail "evidence path is required"
[[ -f "$EVIDENCE" ]] || fail "release evidence is missing: $EVIDENCE"
[[ "$EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "expected version must be strict X.Y.Z"
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] \
  || fail "expected commit must be a 40-character lowercase SHA"

REQUIRED_KEYS=(
  schema_version
  version
  notarization_id
  notarization_status
  codesign
  stapler
  gatekeeper
  bundle_identifier
  bundle_version
  bundle_build
  commit_sha
)

for key in "${REQUIRED_KEYS[@]}"; do
  count="$(grep -c "^${key}=" "$EVIDENCE" || true)"
  [[ "$count" == "1" ]] || fail "evidence must contain exactly one $key"
done

while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || fail "blank evidence lines are not allowed"
  [[ "$line" =~ ^([a-z_]+)=(.+)$ ]] || fail "invalid evidence line: $line"
  key="${BASH_REMATCH[1]}"
  known=false
  for required in "${REQUIRED_KEYS[@]}"; do
    if [[ "$key" == "$required" ]]; then
      known=true
      break
    fi
  done
  [[ "$known" == "true" ]] || fail "unknown evidence key: $key"
done < "$EVIDENCE"

value_for() {
  local key="$1"
  sed -n "s/^${key}=//p" "$EVIDENCE"
}

SCHEMA_VERSION="$(value_for schema_version)"
VERSION="$(value_for version)"
NOTARIZATION_ID="$(value_for notarization_id)"
NOTARIZATION_STATUS="$(value_for notarization_status)"
CODESIGN_STATUS="$(value_for codesign)"
STAPLER_STATUS="$(value_for stapler)"
GATEKEEPER_STATUS="$(value_for gatekeeper)"
BUNDLE_IDENTIFIER="$(value_for bundle_identifier)"
BUNDLE_VERSION="$(value_for bundle_version)"
BUNDLE_BUILD="$(value_for bundle_build)"
COMMIT_SHA="$(value_for commit_sha)"

[[ "$SCHEMA_VERSION" == "1" ]] || fail "unsupported evidence schema version: $SCHEMA_VERSION"
[[ "$VERSION" == "$EXPECTED_VERSION" ]] \
  || fail "evidence version mismatch: expected $EXPECTED_VERSION, got $VERSION"
[[ "$NOTARIZATION_ID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
  || fail "notarization_id is not UUID-shaped: $NOTARIZATION_ID"
[[ "$NOTARIZATION_STATUS" == "Accepted" ]] || fail "notarization status is not Accepted"
[[ "$CODESIGN_STATUS" == "verified" ]] || fail "codesign evidence is not verified"
[[ "$STAPLER_STATUS" == "validated" ]] || fail "stapler evidence is not validated"
[[ "$GATEKEEPER_STATUS" == "accepted" ]] || fail "Gatekeeper evidence is not accepted"
[[ "$BUNDLE_IDENTIFIER" == "io.github.lamy210.schneeglass" ]] \
  || fail "unexpected bundle identifier: $BUNDLE_IDENTIFIER"
[[ "$BUNDLE_VERSION" == "$EXPECTED_VERSION" ]] \
  || fail "signed bundle version mismatch: expected $EXPECTED_VERSION, got $BUNDLE_VERSION"
[[ "$BUNDLE_BUILD" =~ ^[1-9][0-9]*$ ]] \
  || fail "signed bundle build must be a positive integer: $BUNDLE_BUILD"
[[ "$COMMIT_SHA" == "$EXPECTED_COMMIT" ]] \
  || fail "candidate source commit mismatch: expected $EXPECTED_COMMIT, got $COMMIT_SHA"

echo "Release evidence OK: schema=$SCHEMA_VERSION version=$VERSION build=$BUNDLE_BUILD commit=$COMMIT_SHA"
