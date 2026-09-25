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
    case "$MODE" in
      environment-case-title)
        printf '[{"total_count":1,"environments":[{"name":"Production-Release"}]}]\n'
        ;;
      environment-case-mixed)
        printf '[{"total_count":1,"environments":[{"name":"PrOdUcTiOn-ReLeAsE"}]}]\n'
        ;;
      *)
        printf '[{"total_count":1,"environments":[{"name":"production-release"}]}]\n'
        ;;
    esac
    ;;
  GET:repos/example/SchneeGlass/environments/production-release)
    if [[ "$MODE" == 'final-environment-drift' ]]; then
      detail_reads="$(grep -Fc 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/environments/production-release ' "$LOG")"
      if [[ "$detail_reads" -le 1 ]]; then
        printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n'
      else
        printf '{"name":"production-release","protection_rules":[{"type":"branch_policy"}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":false}}\n'
      fi
      break
    fi
    case "$MODE" in
      environment-case-title)
        environment_name='Production-Release'
        ;;
      environment-case-mixed)
        environment_name='PrOdUcTiOn-ReLeAsE'
        ;;
      *)
        environment_name='production-release'
        ;;
    esac
    printf '{"name":"%s","protection_rules":[{"type":"branch_policy"},{"type":"wait_timer","wait_timer":10}],"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}\n' "$environment_name"
    ;;
  GET:repos/example/SchneeGlass/environments/production-release/deployment-branch-policies?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    if [[ "$MODE" == 'extra-policy' ]]; then
      printf '[{"total_count":2,"branch_policies":[{"id":101,"name":"main","type":"branch"},{"id":102,"name":"release/*","type":"branch"}]}]\n'
    elif [[ "$MODE" == 'incomplete-policy-enumeration' ]]; then
      printf '[{"total_count":2,"branch_policies":[{"id":101,"name":"main","type":"branch"}]}]\n'
    elif [[ "$MODE" == 'main-tag-policy' ]]; then
      printf '[{"total_count":1,"branch_policies":[{"id":101,"name":"main","type":"tag"}]}]\n'
    elif [[ "$MODE" == 'missing-policy-type' ]]; then
      printf '[{"total_count":1,"branch_policies":[{"id":101,"name":"main"}]}]\n'
    elif [[ "$MODE" == 'missing-policy' && ! -f "$POLICY_CREATED" ]]; then
      printf '[{"total_count":0,"branch_policies":[]}]\n'
    elif [[ "$MODE" == 'concurrent-policy-recovery' ]]; then
      policy_reads="$(grep -Fc 'deployment-branch-policies\?per_page=100' "$LOG")"
      if [[ "$policy_reads" -le 1 && ! -f "$POLICY_CREATED" ]]; then
        printf '[{"total_count":0,"branch_policies":[]}]\n'
      else
        printf '[{"total_count":1,"branch_policies":[{"id":101,"name":"main","type":"branch"}]}]\n'
      fi
    else
      printf '[{"total_count":1,"branch_policies":[{"id":101,"name":"main","type":"branch"}]}]\n'
    fi
    ;;
  POST:repos/example/SchneeGlass/environments/production-release/deployment-branch-policies)
    [[ "$MODE" == 'missing-policy' || "$MODE" == 'concurrent-policy-recovery' ]] || {
      echo "unexpected deployment policy mutation: $METHOD $ENDPOINT" >&2
      exit 93
    }
    touch "$POLICY_CREATED"
    printf '{"id":101,"name":"main","type":"branch"}\n'
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
      printf '3\n'
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
  local count=''
  local status=0

  if count="$(grep -Fc -- "$pattern" "$LOG")"; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -ne 0 ]]; then
    echo "Fixture log-count assertion failed: unable to enumerate pattern: $pattern (grep status $status)" >&2
    return 1
  fi
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    echo "Fixture log-count assertion failed: count is not numeric for pattern: $pattern ($count)" >&2
    return 1
  fi
  if [[ "$count" -ne "$expected" ]]; then
    echo "Fixture log-count assertion failed: expected $expected match(es) for pattern: $pattern, found $count" >&2
    return 1
  fi
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
grep -Fq 'Production release Environment verified: production-release allows only exact main branch policy' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# GitHub Environment names are case-insensitive. Existing case variants must be
# recognized as the same target and verified without creation/update mutation.
for environment_case_mode in environment-case-title environment-case-mixed
do
  : > "$LOG"
  export GH_FIXTURE_MODE="$environment_case_mode"
  OUTPUT="$FIXTURE/$environment_case_mode.log"
  set +e
  bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
  STATUS=$?
  set -e

  if [[ "$STATUS" -ne 0 ]]; then
    cat "$OUTPUT" >&2
    cat "$LOG" >&2
    exit "$STATUS"
  fi

  grep -Fq 'Production release Environment verified: production-release allows only exact main branch policy' "$OUTPUT"
  ! grep -Fq -- '--method PUT' "$LOG"
  ! grep -Fq -- '--method POST' "$LOG"
done

# Final certification must re-read Environment detail. A concurrent settings
# drift after the initial detail check must fail even when exact main policy stays valid.
: > "$LOG"
export GH_FIXTURE_MODE='final-environment-drift'
OUTPUT="$FIXTURE/final-environment-drift.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Production release environment setup failed: production-release must resolve case-insensitively and use custom deployment branch policies' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Incomplete pagination must not be certified from the observed subset when the
# API reports more policies than were returned.
: > "$LOG"
export GH_FIXTURE_MODE='incomplete-policy-enumeration'
OUTPUT="$FIXTURE/incomplete-policy-enumeration.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT" >&2
  cat "$LOG" >&2
  echo 'Production release Environment unexpectedly accepted incomplete policy enumeration.' >&2
  exit 1
fi
grep -Fq 'Production release environment setup failed: deployment branch policy enumeration is incomplete' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# A main-named tag policy must not be certified as the protected main branch.
: > "$LOG"
export GH_FIXTURE_MODE='main-tag-policy'
OUTPUT="$FIXTURE/main-tag-policy.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT" >&2
  cat "$LOG" >&2
  echo 'Production release Environment unexpectedly accepted a main tag policy.' >&2
  exit 1
fi
grep -Fq 'Production release environment setup failed: production-release must contain exactly one deployment policy for branch main' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# A policy object without an explicit type must fail closed.
: > "$LOG"
export GH_FIXTURE_MODE='missing-policy-type'
OUTPUT="$FIXTURE/missing-policy-type.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT" >&2
  cat "$LOG" >&2
  echo 'Production release Environment unexpectedly accepted a policy without type.' >&2
  exit 1
fi
grep -Fq 'Production release environment setup failed: deployment branch policy response is malformed' "$OUTPUT"
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
grep -Fq 'Production release environment setup failed: production-release must contain exactly one deployment policy for branch main' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

# Recovery safety: a concurrent exact main policy appearing after the first
# empty policy read must block the recovery POST.
: > "$LOG"
rm -f "$POLICY_CREATED"
export GH_FIXTURE_MODE='concurrent-policy-recovery'
OUTPUT="$FIXTURE/concurrent-policy-recovery.log"
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Production release environment setup failed: production-release deployment policy appeared before creation; refusing policy mutation' "$OUTPUT"
assert_log_count 2 'deployment-branch-policies\?per_page=100'
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
grep -Fq 'Production release Environment verified: production-release allows only exact main branch policy' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
assert_log_count 1 '--method POST'
grep -Fq 'repos/example/SchneeGlass/environments/production-release/deployment-branch-policies' "$LOG"
assert_log_count 3 'deployment-branch-policies\?per_page=100'

# Count assertions must reject partial expected output followed by an enumeration failure.
export GH_FIXTURE_GREP_MODE='partial-count-failure'
for assertion in \
  '1|--method POST' \
  '3|deployment-branch-policies\?per_page=100'
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
