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
    if [[ "$MODE" == 'protected-missing-rules' ]]; then
      printf '[[]]\n'
    else
      cat <<'JSON'
[[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"required_review_thread_resolution":true}}]]
JSON
    fi
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

# Safety gate 1: an unprotected main must stop before any Environment mutation.
export GH_FIXTURE_MODE='unprotected'
OUTPUT="$FIXTURE/unprotected.log"
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
set +e
bash Scripts/setup-production-release-environment.sh example/SchneeGlass >"$OUTPUT" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release required-check verification failed: missing required status check from app ID 15368: Canonical / Xcode 26.6 / App Build / Safety Guards' "$OUTPUT"
! grep -Fq -- '--method PUT' "$LOG"
! grep -Fq -- '--method POST' "$LOG"

rm -rf "$FIXTURE"
echo 'Production release Environment governance gate fixtures passed'
