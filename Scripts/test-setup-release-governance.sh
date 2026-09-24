#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-governance-setup-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/gh.log"
: > "$LOG"
REAL_JQ="$(command -v jq)"
export REAL_JQ

RULESET_RECIPE='.github/rulesets/main-release-governance.json'
RULESET_RECIPE_BACKUP="$FIXTURE/main-release-governance.json"
cp "$RULESET_RECIPE" "$RULESET_RECIPE_BACKUP"

cleanup() {
  if [[ -f "$RULESET_RECIPE_BACKUP" ]]; then
    cp "$RULESET_RECIPE_BACKUP" "$RULESET_RECIPE"
  fi
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

cat > "$FIXTURE/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

LOG="${GH_FIXTURE_LOG:?}"
MODE="${GH_FIXTURE_MODE:-empty}"
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
    --input)
      INPUT="$2"
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
    --jq)
      echo 'fixture does not support gh api --jq' >&2
      exit 91
      ;;
    *)
      ENDPOINT="$1"
      shift
      ;;
  esac
done

emit_canonical_ruleset_detail() {
  local id="$1"
  cat <<JSON
{"id":$id,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Compatibility / macOS 15 / App Build","integration_id":15368},{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368}],"strict_required_status_checks_policy":true,"do_not_enforce_on_create":false}},{"type":"pull_request","parameters":{"allowed_merge_methods":["rebase","merge","squash"],"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_last_push_approval":false,"required_approving_review_count":0,"required_review_thread_resolution":true}},{"type":"non_fast_forward"},{"type":"deletion"}]}
JSON
}

case "$METHOD:$ENDPOINT" in
  GET:repos/example/SchneeGlass/rulesets)
    case "$MODE" in
      concurrent-layer|concurrent-replace|concurrent-disable|post-mutation-layer)
        if grep -Fq 'api --method POST repos/example/SchneeGlass/rulesets ' "$LOG"; then
          case "$MODE" in
            concurrent-layer)
              printf '[{"id":123,"name":"SchneeGlass main release governance","enforcement":"active"},{"id":77,"name":"Concurrent unrelated policy","enforcement":"active"}]\n'
              ;;
            concurrent-replace)
              printf '[{"id":999,"name":"SchneeGlass main release governance","enforcement":"active"}]\n'
              ;;
            concurrent-disable)
              printf '[{"id":123,"name":"SchneeGlass main release governance","enforcement":"disabled"}]\n'
              ;;
            post-mutation-layer)
              if grep -Fq 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"; then
                printf '[{"id":123,"name":"SchneeGlass main release governance","enforcement":"active"},{"id":77,"name":"Concurrent unrelated policy","enforcement":"active"}]\n'
              else
                printf '[{"id":123,"name":"SchneeGlass main release governance","enforcement":"active"}]\n'
              fi
              ;;
          esac
        else
          printf '[]\n'
        fi
        ;;
      empty|post-mutation-drift)
        if grep -Fq 'api --method POST repos/example/SchneeGlass/rulesets ' "$LOG"; then
          printf '[{"id":123,"name":"SchneeGlass main release governance","enforcement":"active"}]\n'
        else
          printf '[]\n'
        fi
        ;;
      duplicate|bypass|missing-bypass|invalid-bypass|wrong-target|drifted-pr|extra-rule)
        printf '[{"id":55,"name":"SchneeGlass main release governance","enforcement":"active"}]\n'
        ;;
      inactive)
        printf '[{"id":55,"name":"SchneeGlass main release governance","enforcement":"disabled"}]\n'
        ;;
      mixed)
        printf '[{"id":55,"name":"SchneeGlass main release governance","enforcement":"active"},{"id":77,"name":"Existing unrelated policy","enforcement":"active"}]\n'
        ;;
      unrelated)
        printf '[{"id":77,"name":"Existing unrelated policy","enforcement":"active"}]\n'
        ;;
      *)
        printf '[]\n'
        ;;
    esac
    ;;
  POST:repos/example/SchneeGlass/rulesets)
    [[ -n "$INPUT" && -f "$INPUT" ]]
    printf '{"id":123,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}}}\n'
    ;;
  GET:repos/example/SchneeGlass/rulesets/123)
    if [[ "$MODE" == 'post-mutation-drift' ]] && grep -Fq 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"; then
      cat <<'JSON'
{"id":123,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Compatibility / macOS 15 / App Build","integration_id":15368},{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368}],"strict_required_status_checks_policy":true,"do_not_enforce_on_create":false}},{"type":"pull_request","parameters":{"allowed_merge_methods":["rebase","merge","squash"],"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_last_push_approval":false,"required_approving_review_count":1,"required_review_thread_resolution":true}},{"type":"non_fast_forward"},{"type":"deletion"}]}
JSON
    else
      emit_canonical_ruleset_detail 123
    fi
    ;;
  GET:repos/example/SchneeGlass/rulesets/55)
    case "$MODE" in
      bypass)
        printf '{"id":55,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}}}\n'
        ;;
      missing-bypass)
        printf '{"id":55,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}}}\n'
        ;;
      invalid-bypass)
        printf '{"id":55,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":{},"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}}}\n'
        ;;
      wrong-target)
        printf '{"id":55,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/release"],"exclude":[]}}}\n'
        ;;
      drifted-pr)
        cat <<'JSON'
{"id":55,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"allowed_merge_methods":["merge","squash","rebase"],"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_last_push_approval":false,"required_approving_review_count":1,"required_review_thread_resolution":true}},{"type":"required_status_checks","parameters":{"do_not_enforce_on_create":false,"required_status_checks":[{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368},{"context":"Compatibility / macOS 15 / App Build","integration_id":15368}],"strict_required_status_checks_policy":true}}]}
JSON
        ;;
      extra-rule)
        cat <<'JSON'
{"id":55,"name":"SchneeGlass main release governance","target":"branch","enforcement":"active","bypass_actors":[],"conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},"rules":[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"allowed_merge_methods":["merge","squash","rebase"],"dismiss_stale_reviews_on_push":false,"require_code_owner_review":false,"require_last_push_approval":false,"required_approving_review_count":0,"required_review_thread_resolution":true}},{"type":"required_status_checks","parameters":{"do_not_enforce_on_create":false,"required_status_checks":[{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368},{"context":"Compatibility / macOS 15 / App Build","integration_id":15368}],"strict_required_status_checks_policy":true}},{"type":"required_signatures"}]}
JSON
        ;;
      *)
        emit_canonical_ruleset_detail 55
        ;;
    esac
    ;;
  PUT:repos/example/SchneeGlass/immutable-releases)
    ;;
  GET:repos/example/SchneeGlass/immutable-releases)
    printf '{"enabled":true,"enforced_by_owner":false}\n'
    ;;
  GET:repos/example/SchneeGlass/branches/main)
    cat <<'JSON'
{"name":"main","protected":true,"protection":{"enabled":true,"required_status_checks":{"contexts":[],"checks":[]}}}
JSON
    ;;
  GET:repos/example/SchneeGlass/rules/branches/main?per_page=100)
    [[ "$PAGINATE" == true && "$SLURP" == true ]]
    cat <<'JSON'
[[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"required_review_thread_resolution":true}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368},{"context":"Compatibility / macOS 15 / App Build","integration_id":15368}],"strict_required_status_checks_policy":true}}]]
JSON
    ;;
  *)
    echo "unexpected gh api request: $METHOD $ENDPOINT" >&2
    exit 92
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/gh"

cat > "$FIXTURE/bin/jq" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${GH_FIXTURE_JQ_MODE:-}" == 'partial-length-failure' && "${1:-}" == 'length' ]]; then
  printf '1\n'
  exit 42
fi

exec "${REAL_JQ:?}" "$@"
SHIM
chmod +x "$FIXTURE/bin/jq"

export GH_FIXTURE_LOG="$LOG"
export PATH="$FIXTURE/bin:$PATH"

# Happy path: no rulesets exist, so create once, verify the created canonical ruleset detail,
# enable immutability, then verify live governance.
export GH_FIXTURE_MODE='empty'
bash Scripts/setup-release-governance.sh example/SchneeGlass

grep -Fq 'api repos/example/SchneeGlass/rulesets' "$LOG"
grep -Fq 'api --method POST repos/example/SchneeGlass/rulesets --input .github/rulesets/main-release-governance.json' "$LOG"
grep -Fq 'repos/example/SchneeGlass/rulesets/123' "$LOG"
grep -Fq 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api repos/example/SchneeGlass/branches/main' "$LOG"
grep -Fq 'api --paginate --slurp repos/example/SchneeGlass/rules/branches/main\?per_page=100' "$LOG"

POST_LINE="$(grep -n 'api --method POST repos/example/SchneeGlass/rulesets' "$LOG" | cut -d: -f1)"
DETAIL_COUNT="$(grep -Fc 'repos/example/SchneeGlass/rulesets/123' "$LOG")"
[[ "$DETAIL_COUNT" =~ ^[0-9]+$ ]]
[[ "$DETAIL_COUNT" -eq 2 ]]
INITIAL_DETAIL_LINE="$(grep -n 'repos/example/SchneeGlass/rulesets/123' "$LOG" | sed -n '1s/:.*//p')"
FINAL_DETAIL_LINE="$(grep -n 'repos/example/SchneeGlass/rulesets/123' "$LOG" | sed -n '$s/:.*//p')"
PUT_LINE="$(grep -n 'api --method PUT' "$LOG" | cut -d: -f1)"
BRANCH_LINE="$(grep -n 'api repos/example/SchneeGlass/branches/main' "$LOG" | cut -d: -f1)"
[[ "$POST_LINE" -lt "$INITIAL_DETAIL_LINE" && "$INITIAL_DETAIL_LINE" -lt "$PUT_LINE" && "$PUT_LINE" -lt "$BRANCH_LINE" && "$BRANCH_LINE" -lt "$FINAL_DETAIL_LINE" ]]

# Mutation safety: ruleset exclusivity must be revalidated after canonical detail
# verification. A concurrent unrelated ruleset appearing after the initial empty
# inventory must block immutable-release mutation.
: > "$LOG"
export GH_FIXTURE_MODE='concurrent-layer'
CONCURRENT_LAYER_LOG="$FIXTURE/concurrent-layer.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$CONCURRENT_LAYER_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: repository ruleset inventory changed before immutability mutation' "$CONCURRENT_LAYER_LOG"
grep -Fq 'api --method POST repos/example/SchneeGlass/rulesets --input .github/rulesets/main-release-governance.json' "$LOG"
grep -Fq 'repos/example/SchneeGlass/rulesets/123' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Mutation safety: replacing the canonical ruleset with a same-named different
# identity between detail validation and mutation must fail closed.
: > "$LOG"
export GH_FIXTURE_MODE='concurrent-replace'
CONCURRENT_REPLACE_LOG="$FIXTURE/concurrent-replace.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$CONCURRENT_REPLACE_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: canonical ruleset identity changed before immutability mutation' "$CONCURRENT_REPLACE_LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"

# Mutation safety: enforcement must still be active at the revalidation boundary.
: > "$LOG"
export GH_FIXTURE_MODE='concurrent-disable'
CONCURRENT_DISABLE_LOG="$FIXTURE/concurrent-disable.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$CONCURRENT_DISABLE_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: canonical ruleset enforcement changed before immutability mutation' "$CONCURRENT_DISABLE_LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"

# Final certification safety: a layered ruleset stack appearing only after the
# immutable-release mutation must prevent a successful governance certification.
: > "$LOG"
export GH_FIXTURE_MODE='post-mutation-layer'
POST_MUTATION_LAYER_LOG="$FIXTURE/post-mutation-layer.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$POST_MUTATION_LAYER_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: repository ruleset inventory changed before final certification' "$POST_MUTATION_LAYER_LOG"
grep -Fq 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api repos/example/SchneeGlass/branches/main' "$LOG"
grep -Fq 'api --paginate --slurp repos/example/SchneeGlass/rules/branches/main\?per_page=100' "$LOG"

# Final certification safety: canonical semantics drifting only after immutable
# mutation must also fail even when repository ruleset inventory remains singular.
: > "$LOG"
export GH_FIXTURE_MODE='post-mutation-drift'
POST_MUTATION_DRIFT_LOG="$FIXTURE/post-mutation-drift.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$POST_MUTATION_DRIFT_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Canonical release ruleset verification failed: live ruleset does not match the checked-in canonical recipe' "$POST_MUTATION_DRIFT_LOG"
grep -Fq 'Release governance setup failed: canonical ruleset semantics do not match the checked-in recipe' "$POST_MUTATION_DRIFT_LOG"
grep -Fq 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api repos/example/SchneeGlass/branches/main' "$LOG"

# Partial recovery: a sole active canonical ruleset may be left behind when immutability setup fails.
# Normal setup must resume without duplicating the ruleset, revalidate its bypass policy, enable
# immutability, and re-verify live governance.
: > "$LOG"
export GH_FIXTURE_MODE='duplicate'
bash Scripts/setup-release-governance.sh example/SchneeGlass

! grep -Fq -- '--method POST' "$LOG"
grep -Fq 'repos/example/SchneeGlass/rulesets/55' "$LOG"
grep -Fq 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api repos/example/SchneeGlass/branches/main' "$LOG"
grep -Fq 'api --paginate --slurp repos/example/SchneeGlass/rules/branches/main\?per_page=100' "$LOG"

# Recovery safety: an inactive canonical ruleset is not a resumable partial setup.
: > "$LOG"
export GH_FIXTURE_MODE='inactive'
INACTIVE_SETUP_LOG="$FIXTURE/inactive-setup.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$INACTIVE_SETUP_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: matching ruleset exists but enforcement is not active: SchneeGlass main release governance' "$INACTIVE_SETUP_LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"

# Recovery safety: a layered ruleset stack remains ambiguous and must not be mutated.
: > "$LOG"
export GH_FIXTURE_MODE='mixed'
LAYERED_SETUP_LOG="$FIXTURE/layered-setup.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$LAYERED_SETUP_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: matching ruleset already exists: SchneeGlass main release governance' "$LAYERED_SETUP_LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"

# Verify-only: an existing canonical ruleset can be revalidated without mutating repository policy.
: > "$LOG"
export GH_FIXTURE_MODE='duplicate'
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only

grep -Fq 'api repos/example/SchneeGlass/rulesets' "$LOG"
grep -Fq 'repos/example/SchneeGlass/rulesets/55' "$LOG"
grep -Fq 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api repos/example/SchneeGlass/branches/main' "$LOG"
grep -Fq 'api --paginate --slurp repos/example/SchneeGlass/rules/branches/main\?per_page=100' "$LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"

# Verify-only must fail closed when ruleset-count enumeration returns partial output and fails.
# The old implementation embedded jq inside [[ ... ]] and could mask exit 42 when the
# partial output happened to be the trusted count "1".
: > "$LOG"
export GH_FIXTURE_MODE='duplicate'
export GH_FIXTURE_JQ_MODE='partial-length-failure'
VERIFY_PARTIAL_COUNT_LOG="$FIXTURE/verify-partial-count.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_PARTIAL_COUNT_LOG" 2>&1
STATUS=$?
set -e
unset GH_FIXTURE_JQ_MODE

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: unable to enumerate repository ruleset count (jq status 42)' "$VERIFY_PARTIAL_COUNT_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Verify-only must fail closed when the canonical ruleset grants a bypass actor.
: > "$LOG"
export GH_FIXTURE_MODE='bypass'
VERIFY_BYPASS_LOG="$FIXTURE/verify-bypass.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_BYPASS_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: canonical ruleset must not define bypass actors' "$VERIFY_BYPASS_LOG"
grep -Fq 'repos/example/SchneeGlass/rulesets/55' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Missing bypass_actors means the administrator helper could not observe the sensitive policy.
: > "$LOG"
export GH_FIXTURE_MODE='missing-bypass'
VERIFY_MISSING_BYPASS_LOG="$FIXTURE/verify-missing-bypass.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_MISSING_BYPASS_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: canonical ruleset bypass actors are not observable; authenticate with ruleset write access' "$VERIFY_MISSING_BYPASS_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# A malformed bypass_actors value must also fail closed.
: > "$LOG"
export GH_FIXTURE_MODE='invalid-bypass'
VERIFY_INVALID_BYPASS_LOG="$FIXTURE/verify-invalid-bypass.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_INVALID_BYPASS_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: canonical ruleset bypass actors are not observable; authenticate with ruleset write access' "$VERIFY_INVALID_BYPASS_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# The detailed canonical ruleset must still target exactly main.
: > "$LOG"
export GH_FIXTURE_MODE='wrong-target'
VERIFY_WRONG_TARGET_LOG="$FIXTURE/verify-wrong-target.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_WRONG_TARGET_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: canonical ruleset detail does not match the release governance baseline' "$VERIFY_WRONG_TARGET_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# The checked-in mutation recipe must reject bypass actors before any GitHub API call.
: > "$LOG"
export GH_FIXTURE_MODE='empty'
RECIPE_BYPASS_LOG="$FIXTURE/recipe-bypass.log"
"$REAL_JQ" '.bypass_actors = [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]' \
  "$RULESET_RECIPE_BACKUP" > "$RULESET_RECIPE"

set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$RECIPE_BYPASS_LOG" 2>&1
STATUS=$?
set -e
cp "$RULESET_RECIPE_BACKUP" "$RULESET_RECIPE"

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Canonical release ruleset verification failed: canonical recipe contains missing, malformed, or unreviewed fields' "$RECIPE_BYPASS_LOG"
grep -Fq 'Release governance setup failed: canonical ruleset recipe does not match the fixed release governance baseline' "$RECIPE_BYPASS_LOG"
! grep -Fq 'api ' "$LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"

# An unreviewed parameter on a known rule must fail before any GitHub API call.
: > "$LOG"
export GH_FIXTURE_MODE='empty'
RECIPE_EXTRA_FIELD_LOG="$FIXTURE/recipe-extra-field.log"
"$REAL_JQ" '
  .rules |= map(
    if .type == "pull_request" then
      .parameters.unreviewed_future_switch = true
    else
      .
    end
  )
' "$RULESET_RECIPE_BACKUP" > "$RULESET_RECIPE"

set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$RECIPE_EXTRA_FIELD_LOG" 2>&1
STATUS=$?
set -e
cp "$RULESET_RECIPE_BACKUP" "$RULESET_RECIPE"

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Canonical release ruleset verification failed: canonical recipe contains missing, malformed, or unreviewed fields' "$RECIPE_EXTRA_FIELD_LOG"
grep -Fq 'Release governance setup failed: canonical ruleset recipe does not match the fixed release governance baseline' "$RECIPE_EXTRA_FIELD_LOG"
! grep -Fq 'api ' "$LOG"

# Recipe target drift must fail before any GitHub API call.
: > "$LOG"
export GH_FIXTURE_MODE='empty'
RECIPE_TARGET_LOG="$FIXTURE/recipe-target.log"
"$REAL_JQ" '.conditions.ref_name.include = ["refs/heads/release"]' \
  "$RULESET_RECIPE_BACKUP" > "$RULESET_RECIPE"

set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$RECIPE_TARGET_LOG" 2>&1
STATUS=$?
set -e
cp "$RULESET_RECIPE_BACKUP" "$RULESET_RECIPE"

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Canonical release ruleset verification failed: canonical recipe does not match the fixed release governance baseline' "$RECIPE_TARGET_LOG"
grep -Fq 'Release governance setup failed: canonical ruleset recipe does not match the fixed release governance baseline' "$RECIPE_TARGET_LOG"
! grep -Fq 'api ' "$LOG"

# Required-check integration drift must also fail before mutation.
: > "$LOG"
export GH_FIXTURE_MODE='empty'
RECIPE_CHECK_LOG="$FIXTURE/recipe-check.log"
"$REAL_JQ" '
  .rules |= map(
    if .type == "required_status_checks" then
      .parameters.required_status_checks[0].integration_id = 999
    else
      .
    end
  )
' "$RULESET_RECIPE_BACKUP" > "$RULESET_RECIPE"

set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$RECIPE_CHECK_LOG" 2>&1
STATUS=$?
set -e
cp "$RULESET_RECIPE_BACKUP" "$RULESET_RECIPE"

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Canonical release ruleset verification failed: canonical recipe does not match the fixed release governance baseline' "$RECIPE_CHECK_LOG"
grep -Fq 'Release governance setup failed: canonical ruleset recipe does not match the fixed release governance baseline' "$RECIPE_CHECK_LOG"
! grep -Fq 'api ' "$LOG"

# Verify-only must reject drift in reviewed pull-request rule parameters.
: > "$LOG"
export GH_FIXTURE_MODE='drifted-pr'
VERIFY_DRIFTED_PR_LOG="$FIXTURE/verify-drifted-pr.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_DRIFTED_PR_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Canonical release ruleset verification failed: live ruleset does not match the checked-in canonical recipe' "$VERIFY_DRIFTED_PR_LOG"
grep -Fq 'Release governance setup failed: canonical ruleset semantics do not match the checked-in recipe' "$VERIFY_DRIFTED_PR_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Normal recovery must also reject a sole canonical-named ruleset with an extra rule
# before mutating immutability or certifying branch governance.
: > "$LOG"
export GH_FIXTURE_MODE='extra-rule'
EXTRA_RULE_LOG="$FIXTURE/extra-rule.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$EXTRA_RULE_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Canonical release ruleset verification failed: live ruleset does not match the checked-in canonical recipe' "$EXTRA_RULE_LOG"
grep -Fq 'Release governance setup failed: canonical ruleset semantics do not match the checked-in recipe' "$EXTRA_RULE_LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Verify-only must fail closed when the canonical ruleset is absent.
: > "$LOG"
export GH_FIXTURE_MODE='empty'
VERIFY_MISSING_LOG="$FIXTURE/verify-missing.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_MISSING_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: verify-only requires canonical ruleset: SchneeGlass main release governance' "$VERIFY_MISSING_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Verify-only must reject layered rulesets instead of certifying an ambiguous governance stack.
: > "$LOG"
export GH_FIXTURE_MODE='mixed'
VERIFY_LAYERED_LOG="$FIXTURE/verify-layered.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_LAYERED_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: verify-only requires canonical ruleset to be the only repository ruleset' "$VERIFY_LAYERED_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Verify-only must reject a present-but-inactive canonical ruleset before certifying live governance.
: > "$LOG"
export GH_FIXTURE_MODE='inactive'
VERIFY_INACTIVE_LOG="$FIXTURE/verify-inactive.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass --verify-only >"$VERIFY_INACTIVE_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: verify-only requires canonical ruleset enforcement=active' "$VERIFY_INACTIVE_LOG"
! grep -Fq 'immutable-releases' "$LOG"
! grep -Fq 'branches/main' "$LOG"

# Layering safety: any pre-existing differently named ruleset requires manual review.
: > "$LOG"
export GH_FIXTURE_MODE='unrelated'
UNRELATED_LOG="$FIXTURE/unrelated.log"
set +e
bash Scripts/setup-release-governance.sh example/SchneeGlass >"$UNRELATED_LOG" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release governance setup failed: repository already has rulesets; review existing policy before applying the canonical recipe' "$UNRELATED_LOG"
! grep -Fq -- '--method POST' "$LOG"
! grep -Fq 'immutable-releases' "$LOG"

echo 'Release governance setup fixtures passed'
