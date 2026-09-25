#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Production release environment setup failed: $*" >&2
  exit 1
}

[[ "$#" -ge 1 && "$#" -le 2 ]] \
  || fail "usage: $0 <owner/repo> [--verify-credential-names]"
REPOSITORY="$1"
MODE="${2:-}"
[[ -z "$MODE" || "$MODE" == '--verify-credential-names' ]] \
  || fail "usage: $0 <owner/repo> [--verify-credential-names]"
[[ "$REPOSITORY" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]] \
  || fail "repository must be owner/repo"

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"
gh auth status >/dev/null

ENVIRONMENT_NAME='production-release'
API_VERSION='2026-03-10'

TMP="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

BRANCH_JSON="$TMP/main-branch.json"
RULES_PAGES_JSON="$TMP/main-rules-pages.json"
ENVIRONMENTS_PAGES_JSON="$TMP/environments-pages.json"
ENVIRONMENT_JSON="$TMP/environment.json"
POLICIES_PAGES_JSON="$TMP/deployment-branch-policies-pages.json"
ENVIRONMENT_PAYLOAD="$TMP/environment-payload.json"
POLICY_PAYLOAD="$TMP/policy-payload.json"
SECRET_NAMES_JSON="$TMP/environment-secret-names.json"
VARIABLE_NAMES_JSON="$TMP/environment-variable-names.json"

load_environment_counts() {
  local pages_json="$1"

  jq -e '
    type == "array" and
    length >= 1 and
    all(.[];
      type == "object" and
      (.total_count | type == "number" and . >= 0 and floor == .) and
      (.environments | type == "array") and
      all(.environments[];
        type == "object" and
        (.name | type == "string" and length > 0)
      )
    )
  ' "$pages_json" >/dev/null \
    || fail "environments response is malformed"

  ENVIRONMENT_REPORTED_COUNT="$(jq -r '.[0].total_count' "$pages_json")"
  jq -e \
    --argjson total "$ENVIRONMENT_REPORTED_COUNT" \
    'all(.[]; .total_count == $total)' \
    "$pages_json" >/dev/null \
    || fail "environment pages disagree on total_count"

  ENVIRONMENT_OBSERVED_COUNT="$(jq '[.[] .environments[]?] | length' "$pages_json")"
  ENVIRONMENT_COUNT="$(jq --arg name "$ENVIRONMENT_NAME" '[.[] .environments[]? | select((.name | ascii_downcase) == ($name | ascii_downcase))] | length' "$pages_json")"

  [[ "$ENVIRONMENT_OBSERVED_COUNT" =~ ^[0-9]+$ ]] \
    || fail "observed environment count is not numeric: $ENVIRONMENT_OBSERVED_COUNT"
  [[ "$ENVIRONMENT_COUNT" =~ ^[0-9]+$ ]] \
    || fail "$ENVIRONMENT_NAME case-insensitive count is not numeric: $ENVIRONMENT_COUNT"
  [[ "$ENVIRONMENT_REPORTED_COUNT" =~ ^[0-9]+$ ]] \
    || fail "reported environment count is not numeric: $ENVIRONMENT_REPORTED_COUNT"

  [[ "$ENVIRONMENT_OBSERVED_COUNT" -eq "$ENVIRONMENT_REPORTED_COUNT" ]] \
    || fail "environment enumeration is incomplete: reported $ENVIRONMENT_REPORTED_COUNT, observed $ENVIRONMENT_OBSERVED_COUNT"
}

validate_environment_detail() {
  local context="$1"

  gh api \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$REPOSITORY/environments/$ENVIRONMENT_NAME" \
    > "$ENVIRONMENT_JSON"

  jq -e --arg name "$ENVIRONMENT_NAME" '
    type == "object" and
    (.name | type == "string" and length > 0) and
    ((.name | ascii_downcase) == ($name | ascii_downcase)) and
    .deployment_branch_policy.protected_branches == false and
    .deployment_branch_policy.custom_branch_policies == true
  ' "$ENVIRONMENT_JSON" >/dev/null \
    || fail "$ENVIRONMENT_NAME must resolve case-insensitively and use custom deployment branch policies"

  [[ -n "$context" ]] || fail "Environment detail validation context must be non-empty"
}

load_deployment_policy_counts() {
  local pages_json="$1"
  local context="$2"

  jq -e '
    type == "array" and
    length >= 1 and
    all(.[];
      type == "object" and
      (.total_count | type == "number" and . >= 0 and floor == .) and
      (.branch_policies | type == "array") and
      all(.branch_policies[];
        type == "object" and
        (.name | type == "string" and length > 0) and
        (.type | type == "string" and (. == "branch" or . == "tag"))
      )
    )
  ' "$pages_json" >/dev/null \
    || fail "$context response is malformed"

  POLICY_REPORTED_COUNT="$(jq -r '.[0].total_count' "$pages_json")"
  jq -e \
    --argjson total "$POLICY_REPORTED_COUNT" \
    'all(.[]; .total_count == $total)' \
    "$pages_json" >/dev/null \
    || fail "$context pages disagree on total_count"

  POLICY_COUNT="$(jq '[.[] .branch_policies[]?] | length' "$pages_json")"
  MAIN_BRANCH_POLICY_COUNT="$(jq '[.[] .branch_policies[]? | select(.name == "main" and .type == "branch")] | length' "$pages_json")"

  [[ "$POLICY_COUNT" =~ ^[0-9]+$ ]] \
    || fail "$context observed policy count is not numeric: $POLICY_COUNT"
  [[ "$MAIN_BRANCH_POLICY_COUNT" =~ ^[0-9]+$ ]] \
    || fail "$context exact main branch policy count is not numeric: $MAIN_BRANCH_POLICY_COUNT"
  [[ "$POLICY_REPORTED_COUNT" =~ ^[0-9]+$ ]] \
    || fail "$context reported policy count is not numeric: $POLICY_REPORTED_COUNT"

  [[ "$POLICY_COUNT" -eq "$POLICY_REPORTED_COUNT" ]] \
    || fail "$context enumeration is incomplete: reported $POLICY_REPORTED_COUNT, observed $POLICY_COUNT"
}

gh api "repos/$REPOSITORY/branches/main" > "$BRANCH_JSON"
jq -e 'type == "object" and (.protected | type == "boolean")' "$BRANCH_JSON" >/dev/null \
  || fail "main branch response is malformed"

MAIN_PROTECTED="$(jq -r '.protected' "$BRANCH_JSON")"
bash Scripts/verify-release-branch-protection.sh main "$MAIN_PROTECTED"

gh api --paginate --slurp \
  "repos/$REPOSITORY/rules/branches/main?per_page=100" \
  > "$RULES_PAGES_JSON"
jq -e 'type == "array" and all(.[]; type == "array")' "$RULES_PAGES_JSON" >/dev/null \
  || fail "active branch rules response is malformed"

bash Scripts/verify-release-required-branch-rules.sh \
  "$RULES_PAGES_JSON" \
  deletion \
  non_fast_forward \
  pull_request

bash Scripts/verify-release-required-checks.sh \
  "$BRANCH_JSON" \
  "$RULES_PAGES_JSON" \
  15368 \
  'Canonical / Xcode 26.6 / App Build / Safety Guards' \
  'Compatibility / macOS 15 / App Build'

gh api --paginate --slurp \
  "repos/$REPOSITORY/environments?per_page=100" \
  > "$ENVIRONMENTS_PAGES_JSON"
load_environment_counts "$ENVIRONMENTS_PAGES_JSON"
[[ "$ENVIRONMENT_COUNT" -le 1 ]] \
  || fail "multiple case-insensitive Environment identities matched $ENVIRONMENT_NAME"

if [[ "$MODE" == '--verify-credential-names' && "$ENVIRONMENT_COUNT" -eq 0 ]]; then
  fail "credential-name verification requires existing Environment: $ENVIRONMENT_NAME"
fi

if [[ "$ENVIRONMENT_COUNT" -eq 0 ]]; then
  gh api --paginate --slurp \
    "repos/$REPOSITORY/environments?per_page=100" \
    > "$ENVIRONMENTS_PAGES_JSON"
  load_environment_counts "$ENVIRONMENTS_PAGES_JSON"
  [[ "$ENVIRONMENT_COUNT" -eq 0 ]] \
    || fail "$ENVIRONMENT_NAME appeared before creation; refusing create-or-update mutation"

  jq -n '{
    deployment_branch_policy: {
      protected_branches: false,
      custom_branch_policies: true
    }
  }' > "$ENVIRONMENT_PAYLOAD"

  gh api \
    --method PUT \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$REPOSITORY/environments/$ENVIRONMENT_NAME" \
    --input "$ENVIRONMENT_PAYLOAD" \
    >/dev/null

fi

validate_environment_detail 'initial Environment detail'

gh api --paginate --slurp \
  -H "X-GitHub-Api-Version: $API_VERSION" \
  "repos/$REPOSITORY/environments/$ENVIRONMENT_NAME/deployment-branch-policies?per_page=100" \
  > "$POLICIES_PAGES_JSON"
load_deployment_policy_counts \
  "$POLICIES_PAGES_JSON" \
  'deployment branch policy'

if [[ -z "$MODE" && "$POLICY_COUNT" -eq 0 ]]; then
  gh api --paginate --slurp \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$REPOSITORY/environments/$ENVIRONMENT_NAME/deployment-branch-policies?per_page=100" \
    > "$POLICIES_PAGES_JSON"
  load_deployment_policy_counts \
    "$POLICIES_PAGES_JSON" \
    'deployment branch policy before creation'

  [[ "$POLICY_COUNT" -eq 0 ]] \
    || fail "$ENVIRONMENT_NAME deployment policy appeared before creation; refusing policy mutation"

  jq -n '{name: "main", type: "branch"}' > "$POLICY_PAYLOAD"

  gh api \
    --method POST \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$REPOSITORY/environments/$ENVIRONMENT_NAME/deployment-branch-policies" \
    --input "$POLICY_PAYLOAD" \
    >/dev/null

  gh api --paginate --slurp \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    "repos/$REPOSITORY/environments/$ENVIRONMENT_NAME/deployment-branch-policies?per_page=100" \
    > "$POLICIES_PAGES_JSON"
  load_deployment_policy_counts \
    "$POLICIES_PAGES_JSON" \
    'deployment branch policy after recovery'
fi

[[ "$POLICY_COUNT" -eq 1 && "$MAIN_BRANCH_POLICY_COUNT" -eq 1 ]] \
  || fail "$ENVIRONMENT_NAME must contain exactly one deployment policy for branch main"

validate_environment_detail 'final Environment detail'

echo "Production release Environment verified: $ENVIRONMENT_NAME allows only exact main branch policy"

if [[ "$MODE" == '--verify-credential-names' ]]; then
  gh secret list \
    --env "$ENVIRONMENT_NAME" \
    --repo "$REPOSITORY" \
    --json name \
    > "$SECRET_NAMES_JSON"
  gh variable list \
    --env "$ENVIRONMENT_NAME" \
    --repo "$REPOSITORY" \
    --json name \
    > "$VARIABLE_NAMES_JSON"

  jq -e 'type == "array" and all(.[]; type == "object" and (.name | type == "string"))' \
    "$SECRET_NAMES_JSON" >/dev/null \
    || fail "Environment secret-name response is malformed"
  jq -e 'type == "array" and all(.[]; type == "object" and (.name | type == "string"))' \
    "$VARIABLE_NAMES_JSON" >/dev/null \
    || fail "Environment variable-name response is malformed"

  for required_secret in \
    DEVELOPER_ID_P12_BASE64 \
    DEVELOPER_ID_P12_PASSWORD \
    APPSTORE_CONNECT_PRIVATE_KEY_BASE64
  do
    jq -e --arg name "$required_secret" 'any(.[]; .name == $name)' "$SECRET_NAMES_JSON" >/dev/null \
      || fail "missing required Environment secret name: $required_secret"
  done

  for required_variable in \
    APPLE_TEAM_ID \
    APPSTORE_CONNECT_KEY_ID \
    APPSTORE_CONNECT_ISSUER_ID
  do
    jq -e --arg name "$required_variable" 'any(.[]; .name == $name)' "$VARIABLE_NAMES_JSON" >/dev/null \
      || fail "missing required Environment variable name: $required_variable"
  done

  validate_environment_detail 'credential-name final Environment detail'

  echo 'Production release credential names verified: 3 secrets + 3 variables configured'
fi
