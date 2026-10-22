#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo 'jq required for fixtures' >&2; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export MOCK_DIR="$TMP" GH_BIN="$TMP/gh" JQ_BIN="$(command -v jq)"
SHA='0123456789abcdef0123456789abcdef01234567'
DIGEST="sha256:$(printf 'a%.0s' {1..64})"

cat > "$GH_BIN" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  'api repos/Lamy210/SchneeGlass/actions/runs/123456789')
    [[ ! -f "$MOCK_DIR/fail-run" ]] || exit 41
    cat "$MOCK_DIR/run.json"
    ;;
  'api repos/Lamy210/SchneeGlass/branches/main')
    [[ ! -f "$MOCK_DIR/fail-main" ]] || exit 42
    cat "$MOCK_DIR/main.json"
    ;;
  'api --paginate --slurp repos/Lamy210/SchneeGlass/actions/runs/123456789/artifacts?per_page=100')
    [[ ! -f "$MOCK_DIR/fail-artifacts" ]] || exit 43
    cat "$MOCK_DIR/artifacts.json"
    ;;
  *) echo "Unexpected API call: $*" >&2; exit 44 ;;
esac
MOCK
chmod +x "$GH_BIN"

cat > "$TMP/run.json" <<JSON
{
  "id": 123456789,
  "name": "Ad-Hoc Release Candidate",
  "path": ".github/workflows/adhoc-release-candidate.yml",
  "event": "workflow_dispatch",
  "status": "completed",
  "conclusion": "success",
  "head_branch": "main",
  "head_sha": "$SHA",
  "run_attempt": 1,
  "workflow_id": 369218665,
  "repository": {"full_name": "Lamy210/SchneeGlass", "id": 1359347782},
  "head_repository": {"full_name": "Lamy210/SchneeGlass", "id": 1359347782}
}
JSON
cat > "$TMP/main.json" <<JSON
{"name":"main","commit":{"sha":"$SHA"}}
JSON

cat > "$TMP/base-artifacts.json" <<JSON
[
  {
    "total_count": 2,
    "artifacts": [
      {
        "id": 991,
        "name": "unrelated-build-log",
        "size_in_bytes": 100,
        "expired": false,
        "digest": "$DIGEST",
        "workflow_run": {"id": 123456789, "repository_id": 1359347782, "head_repository_id": 1359347782, "head_branch": "main", "head_sha": "$SHA"}
      }
    ]
  },
  {
    "total_count": 2,
    "artifacts": [
      {
        "id": 992,
        "name": "SchneeGlass-0.2.0-adhoc-candidate",
        "size_in_bytes": 8000,
        "expired": false,
        "digest": "$DIGEST",
        "workflow_run": {"id": 123456789, "repository_id": 1359347782, "head_repository_id": 1359347782, "head_branch": "main", "head_sha": "$SHA"}
      }
    ]
  }
]
JSON
cp "$TMP/base-artifacts.json" "$TMP/artifacts.json"

verify() {
  bash Scripts/verify-adhoc-run-artifact-from-github.sh 123456789 0.2.0 "$SHA"
}
reject() {
  local label="$1" diagnostic="$2"; shift 2
  local output
  if output="$("$@" 2>&1)"; then
    echo "Accepted invalid Actions artifact fixture: $label" >&2
    exit 1
  fi
  [[ "$output" == *"$diagnostic"* ]] || {
    echo "Unexpected failure for $label: $output" >&2
    exit 1
  }
}
OUTPUT="$(verify)"
[[ "$OUTPUT" == *'artifact_id=992'* && "$OUTPUT" == *"artifact_digest=$DIGEST"* ]]

mutate_artifacts() {
  local label="$1" filter="$2" expected="$3"
  jq "$filter" "$TMP/base-artifacts.json" > "$TMP/artifacts.json"
  reject "$label" "$expected" verify
  cp "$TMP/base-artifacts.json" "$TMP/artifacts.json"
}

mutate_artifacts 'missing candidate' '.[1].artifacts[0].name="not-a-candidate"' 'expected artifact missing'
mutate_artifacts 'duplicate candidate name' '.[0].artifacts[0].name="SchneeGlass-0.2.0-adhoc-candidate"' 'expected artifact missing'
mutate_artifacts 'duplicate artifact id' '.[1].artifacts[0].id=991' 'artifact pagination or inventory'
mutate_artifacts 'incomplete pagination' '.[1].artifacts=[]' 'artifact pagination or inventory'
mutate_artifacts 'inconsistent total count' '.[1].total_count=3' 'artifact pagination or inventory'
mutate_artifacts 'truncated page list' '.[0:1]' 'artifact pagination or inventory'
mutate_artifacts 'malformed page envelope' '{data: .}' 'artifact pagination or inventory'
mutate_artifacts 'expired artifact' '.[1].artifacts[0].expired=true' 'expected artifact missing'
mutate_artifacts 'missing artifact digest' 'del(.[1].artifacts[0].digest)' 'expected artifact missing'
mutate_artifacts 'invalid digest' '.[1].artifacts[0].digest="md5:bad"' 'expected artifact missing'
mutate_artifacts 'zero size' '.[1].artifacts[0].size_in_bytes=0' 'expected artifact missing'
mutate_artifacts 'other run' '.[1].artifacts[0].workflow_run.id=111' 'expected artifact missing'
mutate_artifacts 'other repo' '.[1].artifacts[0].workflow_run.repository_id=222' 'expected artifact missing'
mutate_artifacts 'other head repo' '.[1].artifacts[0].workflow_run.head_repository_id=222' 'expected artifact missing'
mutate_artifacts 'wrong branch' '.[1].artifacts[0].workflow_run.head_branch="release"' 'expected artifact missing'
mutate_artifacts 'wrong source SHA' '.[1].artifacts[0].workflow_run.head_sha="89abcdef0123456789abcdef0123456789abcdef"' 'expected artifact missing'
mutate_artifacts 'wrong archive id' '.[1].artifacts[0].id=0' 'expected artifact missing'

touch "$TMP/fail-artifacts"
reject 'artifact API unavailable' 'unable to enumerate candidate workflow artifacts' verify
rm "$TMP/fail-artifacts"

touch "$TMP/fail-run"
reject 'candidate run unavailable' 'candidate run provenance or live main check failed' verify
rm "$TMP/fail-run"

touch "$TMP/fail-main"
reject 'current main unavailable' 'candidate run provenance or live main check failed' verify
rm "$TMP/fail-main"

cp "$TMP/run.json" "$TMP/original-run.json"
jq '.head_sha="89abcdef0123456789abcdef0123456789abcdef"' "$TMP/original-run.json" > "$TMP/run.json"
reject 'stale or forged run SHA' 'candidate run provenance or live main check failed' verify
cp "$TMP/original-run.json" "$TMP/run.json"

reject 'invalid run ID' 'run ID must be positive decimal' \
  bash Scripts/verify-adhoc-run-artifact-from-github.sh '0' 0.2.0 "$SHA"
reject 'wrong version syntax' 'version must be X.Y.Z' \
  bash Scripts/verify-adhoc-run-artifact-from-github.sh 123456789 'v0.2.0' "$SHA"
reject 'wrong SHA syntax' 'source SHA must be lowercase 40-hex' \
  bash Scripts/verify-adhoc-run-artifact-from-github.sh 123456789 0.2.0 'bad'
reject 'missing argument' 'usage:' bash Scripts/verify-adhoc-run-artifact-from-github.sh

verify >/dev/null
echo 'GitHub Actions exact-run artifact binding fixtures passed'
