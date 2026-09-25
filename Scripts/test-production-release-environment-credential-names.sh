#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-production-credential-name-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/gh.log"
: > "$LOG"

cat > "$FIXTURE/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

LOG="${GH_FIXTURE_LOG:?}"
MODE="${GH_FIXTURE_MODE:-missing-secret}"
printf '%q ' "$@" >> "$LOG"
printf '\n' >> "$LOG"

if [[ "$1" == 'auth' && "$2" == 'status' ]]; then
  exit 0
fi

if [[ "$1" == 'secret' && "$2" == 'list' ]]; then
  [[ "$*" == *'--env production-release'* ]]
  [[ "$*" == *'--repo example/SchneeGlass'* ]]
  [[ "$*" == *'--json name'* ]]
  if [[ "$MODE" == 'missing-secret' ]]; then
    printf '[{"name":"DEVELOPER_ID_P12_BASE64"},{"name":"DEVELOPER_ID_P12_PASSWORD"}]\n'
  else
    printf '[{"name":"DEVELOPER_ID_P12_BASE64"},{"name":"DEVELOPER_ID_P12_PASSWORD"},{"name":"APPSTORE_CONNECT_PRIVATE_KEY_BASE64"}]\n'
  fi
  exit 0
fi

if [[ "$1" == 'variable' && "$2" == 'list' ]]; then
  [[ "$*" == *'--env production-release'* ]]
  [[ "$*" == *'--repo example/SchneeGlass'* ]]
  [[ "$*" == *'--json name'* ]]
  printf '[{"name":"APPLE_TEAM_ID"},{"name":"APPSTORE_CONNECT_KEY_ID"},{"name":"APPSTORE_CONNECT_ISSUER_ID"}]\n'
  exit 0
fi

[[ "$1" == 'api' ]] || exit 90
shift

METHOD='GET'
PAGINATE=false
SLURP=false
ENDPOINT=''
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --method)
      METHOD="$2"
      shift 2
      ;;
    --paginate)
      PAGINATE=true
      shift
      ;;
    --slurp)
      SLURP=true
      shift
      ;;
    -H|--header)
      shift 2
      ;;
    --input)
      shift 2
      ;;
    *)
      ENDPOINT="$1"
      shift
      ;;
  esac
done

case "$METHOD:$ENDPOINT" in
  GET:repos/example/SchneeGlass/branches/main)
    printf '{"name":"main","protected":true,"protection":{"enabled":true,"required_status_checks":{"contexts":[],"checks":[]}}}\n'
    ;;
  GET:repos/example/SchneeGlass/rules/branches/main?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    cat <<'JSON'
[[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"required_review_thread_resolution":true}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368},{"context":"Compatibility / macOS 15 / App Build","integration_id":15368}],"strict_required_status_checks_policy":true}}]]
JSON
    ;;
  GET:repos/example/SchneeGlass/environments?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    if [[ "$MODE" == 'missing-environment' ]]; then
      printf '[{"total_count":0,"environments":[]}]\n'
    else
      printf '[{"total_count":1,"environments":[{"name":"production-release"}]}]\n'
    fi
    ;;
  GET:repos/example/SchneeGlass/environments/production-release)
    if [[ "$MODE" == 'final-environment-drift' ]]; then
      detail_reads="$(grep -Fc 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/environments/production-release ' "$LOG")"
      if [[ "$detail_reads" -le 1 ]]; then
        printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n'
      else
        printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":false}}\n'
      fi
    else
      printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n'
    fi
    ;;
  GET:repos/example/SchneeGlass/environments/production-release/deployment-branch-policies?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    if [[ "$MODE" == 'missing-policy' ]]; then
      printf '[{"total_count":0,"branch_policies":[]}]\n'
    else
      printf '[{"total_count":1,"branch_policies":[{"id":101,"name":"main","type":"branch"}]}]\n'
    fi
    ;;
  PUT:*|POST:*)
    echo "unexpected mutation during credential-name verification: $METHOD $ENDPOINT" >&2
    exit 93
    ;;
  *)
    echo "unexpected gh api request: $METHOD $ENDPOINT" >&2
    exit 92
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/gh"

export GH_FIXTURE_LOG="$LOG"
export PATH="$FIXTURE/bin:$PATH"

# A verification command must never create the Environment it intends to inspect.
export GH_FIXTURE_MODE='missing-environment'
OUTPUT="$FIXTURE/missing-environment.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass --verify-credential-names >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Production release environment setup failed: credential-name verification requires existing Environment: production-release' "$OUTPUT"
grep -Fq 'api --paginate --slurp repos/example/SchneeGlass/environments\?per_page=100' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq 'secret list ' "$LOG"
! grep -Fq 'variable list ' "$LOG"

# Verification must not repair a missing deployment policy; setup mode owns recovery.
: > "$LOG"
export GH_FIXTURE_MODE='missing-policy'
OUTPUT="$FIXTURE/missing-policy.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass --verify-credential-names >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Production release environment setup failed: production-release must contain exactly one deployment policy for branch main' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq 'secret list ' "$LOG"
! grep -Fq 'variable list ' "$LOG"

# Credential-name verification must revalidate final Environment settings before
# consulting credential names or reporting success.
: > "$LOG"
export GH_FIXTURE_MODE='final-environment-drift'
OUTPUT="$FIXTURE/final-environment-drift.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass --verify-credential-names >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Production release environment setup failed: production-release must resolve case-insensitively and use custom deployment branch policies' "$OUTPUT"
! grep -Fq 'secret list ' "$LOG"
! grep -Fq 'variable list ' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Missing secret name must fail without exposing or requesting values.
: > "$LOG"
export GH_FIXTURE_MODE='missing-secret'
OUTPUT="$FIXTURE/missing-secret.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass --verify-credential-names >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Production release environment setup failed: missing required Environment secret name: APPSTORE_CONNECT_PRIVATE_KEY_BASE64' "$OUTPUT"
grep -Fq 'secret list --env production-release --repo example/SchneeGlass --json name' "$LOG"
grep -Fq 'variable list --env production-release --repo example/SchneeGlass --json name' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Complete required names pass. Only names are requested from GitHub CLI.
: > "$LOG"
export GH_FIXTURE_MODE='complete'
OUTPUT="$FIXTURE/complete.log"
bash Scripts/setup-production-release-environment.sh example/SchneeGlass --verify-credential-names >"$OUTPUT" 2>&1

grep -Fq 'Production release credential names verified: 3 secrets + 3 variables configured' "$OUTPUT"
grep -Fq 'secret list --env production-release --repo example/SchneeGlass --json name' "$LOG"
grep -Fq 'variable list --env production-release --repo example/SchneeGlass --json name' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

rm -rf "$FIXTURE"
echo 'Production release credential-name fixtures passed'
