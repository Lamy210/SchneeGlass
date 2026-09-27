#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Production release secret scope validation failed: $*" >&2
  exit 1
}

[[ "$#" -eq 1 ]] || fail "usage: $0 <workflow-path>"
WORKFLOW="$1"
[[ -f "$WORKFLOW" ]] || fail "workflow is missing: $WORKFLOW"

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

JOB_HEADER="$TMP/sign-notarize-job-header.yml"
BUILD_STEP="$TMP/build-step.yml"

set +e
sed -n '/^  sign-notarize:$/,/^    steps:$/p' "$WORKFLOW" > "$JOB_HEADER"
SED_STATUS=$?
set -e
[[ "$SED_STATUS" -eq 0 ]]   || fail "unable to enumerate sign-notarize job header (sed status $SED_STATUS)"
grep -Fqx '  sign-notarize:' "$JOB_HEADER"   || fail "sign-notarize job is missing"
grep -Fqx '    steps:' "$JOB_HEADER"   || fail "sign-notarize steps boundary is missing"

set +e
awk '
  $0 == "      - name: Build signed and notarized release candidate" {
    if (seen) {
      exit 43
    }
    seen = 1
    capture = 1
  }
  capture && $0 ~ /^      - name: / && $0 != "      - name: Build signed and notarized release candidate" {
    exit 0
  }
  capture {
    print
  }
  END {
    if (!seen) {
      exit 42
    }
  }
' "$WORKFLOW" > "$BUILD_STEP"
AWK_STATUS=$?
set -e
[[ "$AWK_STATUS" -eq 0 ]]   || fail "unable to enumerate signing build step (awk status $AWK_STATUS)"

count_exact_line() {
  local path="$1"
  local expected="$2"
  local count=''

  set +e
  count="$(awk -v expected="$expected" '$0 == expected { count += 1 } END { print count + 0 }' "$path")"
  local status=$?
  set -e

  [[ "$status" -eq 0 ]]     || fail "unable to count exact workflow line: $expected"
  [[ "$count" =~ ^[0-9]+$ ]]     || fail "workflow line count is not numeric: $expected"
  printf '%s\n' "$count"
}

count_expression() {
  local path="$1"
  local expression="$2"
  local count=''

  set +e
  count="$(awk -v expression="$expression" 'index($0, expression) { count += 1 } END { print count + 0 }' "$path")"
  local status=$?
  set -e

  [[ "$status" -eq 0 ]]     || fail "unable to count workflow expression: $expression"
  [[ "$count" =~ ^[0-9]+$ ]]     || fail "workflow expression count is not numeric: $expression"
  printf '%s\n' "$count"
}

for secret_name in   DEVELOPER_ID_P12_BASE64   DEVELOPER_ID_P12_PASSWORD   APPSTORE_CONNECT_PRIVATE_KEY_BASE64
do
  expression="${{ secrets.$secret_name }}"
  expected_line="          $secret_name: $expression"

  [[ "$(count_expression "$WORKFLOW" "$expression")" -eq 1 ]]     || fail "$secret_name must be referenced exactly once in the workflow"
  [[ "$(count_expression "$JOB_HEADER" "$expression")" -eq 0 ]]     || fail "$secret_name must not be exposed at sign-notarize job scope"
  [[ "$(count_exact_line "$BUILD_STEP" "$expected_line")" -eq 1 ]]     || fail "$secret_name must be injected exactly once into the signing build step"
done

for variable_name in   APPLE_TEAM_ID   APPSTORE_CONNECT_KEY_ID   APPSTORE_CONNECT_ISSUER_ID
do
  expression="${{ vars.$variable_name }}"
  expected_line="          $variable_name: $expression"

  [[ "$(count_expression "$WORKFLOW" "$expression")" -eq 1 ]]     || fail "$variable_name must be referenced exactly once in the workflow"
  [[ "$(count_expression "$JOB_HEADER" "$expression")" -eq 0 ]]     || fail "$variable_name must not be exposed at sign-notarize job scope"
  [[ "$(count_exact_line "$BUILD_STEP" "$expected_line")" -eq 1 ]]     || fail "$variable_name must be injected exactly once into the signing build step"
done

echo 'Production release signing credentials are scoped to the build step'
