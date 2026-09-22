#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-existing-production-environment-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/gh.log"
POLICY_CREATED="$FIXTURE/policy-created"
REAL_GREP="$(command -v grep)"
export REAL_GREP
: > "$LOG"

cat > "$FIXTURE/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

LOG="${GH_FIXTURE_LOG:?}"
MODE="${GH_FIXTURE_MODE:-existing-valid}"
POLICY_CREATED="${GH_FIXTURE_POLICY_CREATED:?}"
printf '%q ' "$@" >> "$LOG"
printf '\n' >> "$LOG"

if [[ "$1" == 'auth' && "$2" == 'status' ]]; then
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
    printf '[{"total_count":1,"environments":[{"name":"production-release"}]}]\n'
    ;;
  GET:repos/example/SchneeGlass/environments/production-release)
    printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"},{"type":"wait_timer","wait_timer":10}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n'
    ;;
  GET:repos/example/SchneeGlass/environments/production-release/deployment-branch-policies?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    if [[ "$MODE" == 'extra-policy' ]]; then
      printf '[{"total_count":2,"branch_policies":[{"id":101,"name":"main"},{"id":102,"name":"release/*"}]}]\n'
    elif [[ "$MODE" == 'missing-policy' && ! -f "$POLICY_CREATED" ]]; then
      printf '[{"total_count":0,"branch_policies":[]}]\n'
    else
      printf '[{"total_count":1,"branch_policies":[{"id":101,"name":"main"}]}]\n'
    fi
    ;;
  POST:repos/example/SchneeGlass/environments/production-release/deployment-branch-policies)
    [[ "$MODE" == 'missing-policy' ]] || {
      echo "unexpected deployment policy mutation: $METHOD $ENDPOINT" >&2
      exit 93
    }
    touch "$POLICY_CREATED"
    printf '{"id":101,"name":"main"}\n'
    ;;
  PUT:*|POST:*)
    echo "unexpected mutation for existing Environment: $METHOD $ENDPOINT" >&2
    exit 93
    ;;
  *)
    echo "unexpected gh api request: $METHOD $ENDPOINT" >&2
    exit 92
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/gh"

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${GH_FIXTURE_GREP_MODE:-}" == 'partial-count-failure' && "${1:-}" == '-Fc' ]]; then
  args=("$@")
  pattern=''
  for ((index = 1; index < ${#args[@]}; index += 1)); do
    if [[ "${args[index]}" == '--' ]]; then
      continue
    fi
    pattern="${args[index]}"
    break
  done

  case "$pattern" in
    '--method POST')
      printf '1\n'
      exit 42
      ;;
    'deployment-branch-policies\?per_page=100')
      printf '2\n'
      exit 42
      ;;
  esac
fi

exec "${REAL_GREP:?}" "$@"
SHIM
chmod +x "$FIXTURE/bin/grep"

assert_log_count() {
  local expected="$1"
  local pattern="$2"
  [[ "$(grep -Fc -- "$pattern" "$LOG")" -eq "$expected" ]]
}

export GH_FIXTURE_LOG="$LOG"
export GH_FIXTURE_POLICY_CREATED="$POLICY_CREATED"
export PATH="$FIXTURE/bin:$PATH"

# Existing valid Environment must be verified without overwriting wait timer/reviewer settings.
export GH_FIXTURE_MODE='existing-valid'
OUTPUT="$FIXTURE/existing-valid.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  cat "$LOG" >&2
  exit "$STATUS"
fi
grep -Fq 'Production release Environment verified: production-release allows only exact main policy' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Any extra deployment policy must fail closed and remain non-destructive.
: > "$LOG"
export GH_FIXTURE_MODE='extra-policy'
OUTPUT="$FIXTURE/extra-policy.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Production release environment setup failed: production-release must contain exactly one deployment policy named main' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# A partial prior setup may leave the Environment valid but with no deployment policy.
# Normal setup mode must recover by creating exact main once, then re-read and verify it.
: > "$LOG"
rm -f "$POLICY_CREATED"
export GH_FIXTURE_MODE='missing-policy'
OUTPUT="$FIXTURE/missing-policy.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -ne 0 ]]; then
  cat "$OUTPUT" >&2
  cat "$LOG" >&2
  exit "$STATUS"
fi
grep -Fq 'Production release Environment verified: production-release allows only exact main policy' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
assert_log_count 1 '--method POST'
grep -Fq 'repos/example/SchneeGlass/environments/production-release/deployment-branch-policies' "$LOG"
assert_log_count 2 'deployment-branch-policies\?per_page=100'

# Count assertions must reject partial expected output followed by an enumeration failure.
export GH_FIXTURE_GREP_MODE='partial-count-failure'
for assertion in \
  '1|--method POST' \
  '2|deployment-branch-policies\?per_page=100'
do
  expected="${assertion%%|*}"
  pattern="${assertion#*|}"

  set +e
  assert_log_count "$expected" "$pattern"
  STATUS=$?
  set -e

  if [[ "$STATUS" -eq 0 ]]; then
    echo "Fixture log-count assertion unexpectedly accepted partial output for: $pattern" >&2
    exit 1
  fi
done
unset GH_FIXTURE_GREP_MODE

rm -rf "$FIXTURE"
echo 'Existing production release Environment fixtures passed'
