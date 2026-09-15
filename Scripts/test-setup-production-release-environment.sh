#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-production-environment-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/gh.log"
: > "$LOG"

cat > "$FIXTURE/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

LOG="${GH_FIXTURE_LOG:?}"
MODE="${GH_FIXTURE_MODE:-unprotected}"
printf '%q ' "$@" >> "$LOG"
printf '\n' >> "$LOG"

if [[ "$1" == 'auth' && "$2" == 'status' ]]; then
  exit 0
fi

if [[ "$1" != 'api' ]]; then
  echo "unexpected gh command: $*" >&2
  exit 90
fi
shift

METHOD='GET'
PAGINATE=false
SLURP=false
INPUT=''
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
    --input)
      INPUT="$2"
      shift 2
      ;;
    -H|--header)
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
    if [[ "$MODE" == 'unprotected' ]]; then
      printf '{"name":"main","protected":false,"protection":{"enabled":false,"required_status_checks":{"contexts":[],"checks":[]}}}\n'
    else
      printf '{"name":"main","protected":true,"protection":{"enabled":true,"required_status_checks":{"contexts":[],"checks":[]}}}\n'
    fi
    ;;
  GET:repos/example/SchneeGlass/rules/branches/main?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    case "$MODE" in
      protected-missing-rules)
        printf '[[]]\n'
        ;;
      protected-rules-missing-checks)
        cat <<'JSON'
[[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"required_review_thread_resolution":true}}]]
JSON
        ;;
      *)
        cat <<'JSON'
[[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"required_review_thread_resolution":true}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368},{"context":"Compatibility / macOS 15 / App Build","integration_id":15368}],"strict_required_status_checks_policy":true}}]]
JSON
        ;;
    esac
    ;;
  GET:repos/example/SchneeGlass/environments?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    [[ "$MODE" == 'create-environment' ]]
    printf '[{"total_count":0,"environments":[]}]\n'
    ;;
  PUT:repos/example/SchneeGlass/environments/production-release)
    [[ "$MODE" == 'create-environment' ]]
    [[ -n "$INPUT" && -f "$INPUT" ]]
    jq -e '
      .deployment_branch_policy.protected_branches == false and
      .deployment_branch_policy.custom_branch_policies == true
    ' "$INPUT" >/dev/null
    printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n'
    ;;
  POST:repos/example/SchneeGlass/environments/production-release/deployment-branch-policies)
    [[ "$MODE" == 'create-environment' ]]
    [[ -n "$INPUT" && -f "$INPUT" ]]
    jq -e '.name == "main" and .type == "branch"' "$INPUT" >/dev/null
    printf '{"id":101,"name":"main"}\n'
    ;;
  GET:repos/example/SchneeGlass/environments/production-release)
    [[ "$MODE" == 'create-environment' ]]
    printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n'
    ;;
  GET:repos/example/SchneeGlass/environments/production-release/deployment-branch-policies?per_page=100)
    [[ "$MODE" == 'create-environment' ]]
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    printf '[{"total_count":1,"branch_policies":[{"id":101,"name":"main"}]}]\n'
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

CURRENT_OUTPUT=''
diagnose_on_exit() {
  local status=$?
  trap - EXIT
  if [[ "$status" -ne 0 ]]; then
    echo "=== fixture mode: ${GH_FIXTURE_MODE:-unset} ===" >&2
    echo '=== gh fixture log ===' >&2
    cat "$LOG" >&2 || true
    if [[ -n "$CURRENT_OUTPUT" && -f "$CURRENT_OUTPUT" ]]; then
      echo "=== captured output: $CURRENT_OUTPUT ===" >&2
      cat "$CURRENT_OUTPUT" >&2 || true
    fi
  fi
  exit "$status"
}
trap diagnose_on_exit EXIT

# Safety gate 1: an unprotected main must stop before any Environment mutation.
export GH_FIXTURE_MODE='unprotected'
OUTPUT="$FIXTURE/unprotected.log"
CURRENT_OUTPUT="$OUTPUT"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release branch protection verification failed: main is not protected; configure branch protection or a repository ruleset before publication' "$OUTPUT"
grep -Fq 'api repos/example/SchneeGlass/branches/main' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Safety gate 2: protected=true alone is insufficient; required active rules must exist.
: > "$LOG"
export GH_FIXTURE_MODE='protected-missing-rules'
OUTPUT="$FIXTURE/missing-rules.log"
CURRENT_OUTPUT="$OUTPUT"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release branch-rule verification failed: missing required active branch rule: deletion' "$OUTPUT"
grep -Fq 'api --paginate --slurp repos/example/SchneeGlass/rules/branches/main\?per_page=100' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Safety gate 3: required branch rules without source-bound strict checks are still insufficient.
: > "$LOG"
export GH_FIXTURE_MODE='protected-rules-missing-checks'
OUTPUT="$FIXTURE/missing-checks.log"
CURRENT_OUTPUT="$OUTPUT"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release required-check verification failed: missing required status check from app ID 15368: Canonical / Xcode 26.6 / App Build / Safety Guards' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Happy path: valid governance + missing Environment creates the Environment and exact main policy.
: > "$LOG"
export GH_FIXTURE_MODE='create-environment'
OUTPUT="$FIXTURE/create-environment.log"
CURRENT_OUTPUT="$OUTPUT"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -ne 0 ]]; then
  exit "$STATUS"
fi

assert_log() {
  local needle="$1"
  if ! grep -Fq -- "$needle" "$LOG"; then
    echo "Missing expected gh call: $needle" >&2
    exit 1
  fi
}

assert_log 'api --paginate --slurp repos/example/SchneeGlass/environments\?per_page=100'
assert_log 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/environments/production-release --input'
assert_log 'api --method POST -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/environments/production-release/deployment-branch-policies --input'
assert_log 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/environments/production-release'
assert_log 'api --paginate --slurp -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/environments/production-release/deployment-branch-policies\?per_page=100'
grep -Fq 'Production release Environment verified: production-release allows only exact main policy' "$OUTPUT"

PUT_LINE="$(grep -n -- '--method PUT' "$LOG" | cut -d: -f1)"
POST_LINE="$(grep -n -- '--method POST' "$LOG" | cut -d: -f1)"
VERIFY_LINE="$(grep -Fn 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/environments/production-release ' "$LOG" | cut -d: -f1)"
[[ "$PUT_LINE" -lt "$POST_LINE" && "$POST_LINE" -lt "$VERIFY_LINE" ]]

CURRENT_OUTPUT=''
trap - EXIT
rm -rf "$FIXTURE"
echo 'Production release Environment setup fixtures passed'
