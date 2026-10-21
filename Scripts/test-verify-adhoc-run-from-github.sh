#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo 'jq required for fixtures' >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export MOCK_DIR="$TMP"
export GH_BIN="$TMP/gh"
export JQ_BIN="$(command -v jq)"

cat > "$GH_BIN" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 2 && "$1" == 'api' ]] || exit 2
case "$2" in
  repos/Lamy210/SchneeGlass/actions/runs/123456789)
    [[ ! -f "$MOCK_DIR/fail-run" ]] || exit 1
    cat "$MOCK_DIR/run.json"
    ;;
  repos/Lamy210/SchneeGlass/branches/main)
    [[ ! -f "$MOCK_DIR/fail-main" ]] || exit 1
    cat "$MOCK_DIR/main.json"
    ;;
  *) exit 2 ;;
esac
MOCK
chmod +x "$GH_BIN"

cat > "$TMP/base-run.json" <<'JSON'
{
  "id": 123456789,
  "name": "Ad-Hoc Release Candidate",
  "path": ".github/workflows/adhoc-release-candidate.yml",
  "event": "workflow_dispatch",
  "status": "completed",
  "conclusion": "success",
  "head_branch": "main",
  "head_sha": "0123456789abcdef0123456789abcdef01234567",
  "run_attempt": 1,
  "workflow_id": 369218665,
  "repository": {"full_name": "Lamy210/SchneeGlass", "id": 1359347782},
  "head_repository": {"full_name": "Lamy210/SchneeGlass", "id": 1359347782}
}
JSON

cat > "$TMP/base-main.json" <<'JSON'
{
  "name": "main",
  "commit": {"sha": "0123456789abcdef0123456789abcdef01234567"}
}
JSON
cp "$TMP/base-run.json" "$TMP/run.json"
cp "$TMP/base-main.json" "$TMP/main.json"

verify() {
  bash Scripts/verify-adhoc-run-from-github.sh 123456789
}

reject() {
  local case_name="$1" expected="$2"
  shift 2
  local result
  if result="$("$@" 2>&1)"; then
    echo "Accepted invalid authenticated-run fixture: $case_name" >&2
    exit 1
  fi
  [[ "$result" == *"$expected"* ]] || {
    echo "Wrong diagnostic for $case_name: $result" >&2
    exit 1
  }
}

verify >/dev/null

mutate_run() {
  local case_name="$1" jq_filter="$2" message="$3"
  jq "$jq_filter" "$TMP/base-run.json" > "$TMP/run.json"
  reject "$case_name" "$message" verify
  cp "$TMP/base-run.json" "$TMP/run.json"
}
mutate_main() {
  local case_name="$1" jq_filter="$2" message="$3"
  jq "$jq_filter" "$TMP/base-main.json" > "$TMP/main.json"
  reject "$case_name" "$message" verify
  cp "$TMP/base-main.json" "$TMP/main.json"
}

mutate_run 'different run ID' '.id=111' 'GitHub run identity or metadata is malformed'
mutate_run 'wrong repository' '.repository.full_name="attacker/similar"' 'GitHub run identity or metadata is malformed'
mutate_run 'wrong head repository' '.head_repository.full_name="attacker/repo"' 'GitHub run identity or metadata is malformed'
mutate_run 'cross-repository identity mismatch' '.head_repository.id=999' 'GitHub run identity or metadata is malformed'
mutate_run 'lookalike workflow identity' '.workflow_id=999' 'GitHub run identity or metadata is malformed'
mutate_run 'missing mandatory field' 'del(.path)' 'GitHub run identity or metadata is malformed'
mutate_run 'null conclusion' '.conclusion=null' 'GitHub run identity or metadata is malformed'
mutate_run 'wrong workflow path' '.path=".github/workflows/fake.yml"' 'GitHub run is not an eligible'
mutate_run 'wrong workflow name' '.name="Production Release Candidate"' 'GitHub run is not an eligible'
mutate_run 'untrusted PR event' '.event="pull_request"' 'GitHub run is not an eligible'
mutate_run 'queued run' '.status="queued"' 'GitHub run is not an eligible'
mutate_run 'failed run' '.conclusion="failure"' 'GitHub run is not an eligible'
mutate_run 'wrong branch' '.head_branch="release"' 'GitHub run is not an eligible'
mutate_run 'all-zero candidate SHA' '.head_sha="0000000000000000000000000000000000000000"' 'GitHub run is not an eligible'
mutate_run 'replayed attempt' '.run_attempt=2' 'GitHub run is not an eligible'
mutate_run 'noninteger attempt' '.run_attempt=1.5' 'GitHub run identity or metadata is malformed'
mutate_run 'stale candidate SHA' '.head_sha="89abcdef0123456789abcdef0123456789abcdef"' 'GitHub run is not an eligible'

mutate_main 'wrong branch response' '.name="release"' 'live main metadata is malformed'
mutate_main 'malformed main commit' '.commit.sha="bad"' 'live main metadata is malformed'
mutate_main 'newer live main' '.commit.sha="89abcdef0123456789abcdef0123456789abcdef"' 'GitHub run is not an eligible'

touch "$TMP/fail-run"
reject 'run API unavailable' 'unable to fetch authenticated GitHub workflow run' verify
rm "$TMP/fail-run"
touch "$TMP/fail-main"
reject 'main API unavailable' 'unable to fetch live GitHub main' verify
rm "$TMP/fail-main"

reject 'bad run ID' 'run ID must be a positive decimal integer' \
  bash Scripts/verify-adhoc-run-from-github.sh 0
reject 'injected run ID' 'run ID must be a positive decimal integer' \
  bash Scripts/verify-adhoc-run-from-github.sh '123;echo unsafe'
reject 'missing argument' 'usage:' bash Scripts/verify-adhoc-run-from-github.sh

verify >/dev/null
echo 'GitHub API candidate-run provenance fixtures passed'
