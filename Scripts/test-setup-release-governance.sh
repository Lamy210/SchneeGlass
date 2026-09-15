#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-governance-setup-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/gh.log"
: > "$LOG"

cat > "$FIXTURE/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

LOG="${GH_FIXTURE_LOG:?}"
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
      # The setup script should consume raw JSON with repository validators.
      echo 'fixture does not support gh api --jq' >&2
      exit 91
      ;;
    *)
      ENDPOINT="$1"
      shift
      ;;
  esac
done

case "$METHOD:$ENDPOINT" in
  GET:repos/example/SchneeGlass/rulesets)
    printf '[]\n'
    ;;
  POST:repos/example/SchneeGlass/rulesets)
    [[ -n "$INPUT" && -f "$INPUT" ]]
    printf '{"id":123,"name":"SchneeGlass main release governance","enforcement":"active"}\n'
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

export GH_FIXTURE_LOG="$LOG"
export PATH="$FIXTURE/bin:$PATH"

bash Scripts/setup-release-governance.sh example/SchneeGlass

grep -Fq 'api repos/example/SchneeGlass/rulesets' "$LOG"
grep -Fq 'api --method POST repos/example/SchneeGlass/rulesets --input .github/rulesets/main-release-governance.json' "$LOG"
grep -Fq 'api --method PUT -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/immutable-releases' "$LOG"
grep -Fq 'api repos/example/SchneeGlass/branches/main' "$LOG"
grep -Fq 'api --paginate --slurp repos/example/SchneeGlass/rules/branches/main\?per_page=100' "$LOG"

POST_LINE="$(grep -n 'api --method POST repos/example/SchneeGlass/rulesets' "$LOG" | cut -d: -f1)"
PUT_LINE="$(grep -n 'api --method PUT' "$LOG" | cut -d: -f1)"
BRANCH_LINE="$(grep -n 'api repos/example/SchneeGlass/branches/main' "$LOG" | cut -d: -f1)"
[[ "$POST_LINE" -lt "$PUT_LINE" && "$PUT_LINE" -lt "$BRANCH_LINE" ]]

rm -rf "$FIXTURE"
echo 'Release governance setup happy-path fixture passed'
