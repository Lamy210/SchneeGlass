#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
command -v jq >/dev/null 2>&1 || { echo 'jq required for QA fixtures' >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export MOCK_DIR="$TMP" GH_BIN="$TMP/gh" JQ_BIN="$(command -v jq)"
SHA='0123456789abcdef0123456789abcdef01234567'
ARCHIVE_SHA="$(printf 'a%.0s' {1..64})"

cat > "$GH_BIN" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 2 && "$1" == 'api' ]] || exit 25
case "$2" in
  repos/Lamy210/SchneeGlass)
    [[ ! -f "$MOCK_DIR/fail-repo" ]] || exit 26
    cat "$MOCK_DIR/repository.json"
    ;;
  repos/Lamy210/SchneeGlass/issues/comments/987654321)
    [[ ! -f "$MOCK_DIR/fail-comment" ]] || exit 27
    cat "$MOCK_DIR/comment.json"
    ;;
  *) echo "Unexpected API call: $2" >&2; exit 28 ;;
esac
MOCK
chmod +x "$GH_BIN"

cat > "$TMP/base-repository.json" <<'JSON'
{
  "id": 1359347782,
  "full_name": "Lamy210/SchneeGlass",
  "owner": {"id": 90091196, "login": "Lamy210", "type": "User"}
}
JSON

cat > "$TMP/base-comment.json" <<JSON
{
  "id": 987654321,
  "issue_url": "https://api.github.com/repos/Lamy210/SchneeGlass/issues/520",
  "author_association": "OWNER",
  "user": {"id": 90091196, "login": "Lamy210", "type": "User"},
  "created_at": "2026-10-22T01:02:03Z",
  "updated_at": "2026-10-22T01:02:03Z",
  "body": "SCHNEEGLASS_ADHOC_QA_APPROVAL_V1\nrun_id=123456789\nrun_attempt=1\nsource_sha=$SHA\nversion=0.2.0\nbuild=3\narchive_sha256=$ARCHIVE_SHA\nqa_result=pass"
}
JSON
cp "$TMP/base-repository.json" "$TMP/repository.json"
cp "$TMP/base-comment.json" "$TMP/comment.json"

verify() {
  bash Scripts/verify-adhoc-qa-comment-from-github.sh \
    987654321 123456789 0.2.0 3 "$SHA" "$ARCHIVE_SHA"
}
reject() {
  local case_name="$1" message="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    echo "Invalid QA approval fixture passed: $case_name" >&2
    exit 1
  fi
  [[ "$output" == *"$message"* ]] || {
    echo "Unexpected error for $case_name: $output" >&2
    exit 1
  }
}

verify | grep -Fq 'Verified GitHub owner QA approval comment ID=987654321'

mutate_comment() {
  local case_name="$1" filter="$2" error="$3"
  jq "$filter" "$TMP/base-comment.json" > "$TMP/comment.json"
  reject "$case_name" "$error" verify
  cp "$TMP/base-comment.json" "$TMP/comment.json"
}
mutate_repo() {
  local case_name="$1" filter="$2" error="$3"
  jq "$filter" "$TMP/base-repository.json" > "$TMP/repository.json"
  reject "$case_name" "$error" verify
  cp "$TMP/base-repository.json" "$TMP/repository.json"
}

mutate_repo 'different repository' '.full_name="attacker/SchneeGlass"' 'repository or release-authority'
mutate_repo 'repository id changed' '.id=999' 'repository or release-authority'
mutate_repo 'owner id changed' '.owner.id=999' 'repository or release-authority'
mutate_repo 'owner login changed' '.owner.login="attacker"' 'repository or release-authority'
mutate_repo 'owner changed to bot' '.owner.type="Bot"' 'repository or release-authority'

mutate_comment 'different comment ID' '.id=111' 'QA comment is edited'
mutate_comment 'other issue' '.issue_url="https://api.github.com/repos/Lamy210/SchneeGlass/issues/519"' 'QA comment is edited'
mutate_comment 'other repository issue' '.issue_url="https://api.github.com/repos/attacker/SchneeGlass/issues/520"' 'QA comment is edited'
mutate_comment 'different owner id' '.user.id=222' 'QA comment is edited'
mutate_comment 'different login' '.user.login="other-user"' 'QA comment is edited'
mutate_comment 'bot commenter' '.user.type="Bot"' 'QA comment is edited'
mutate_comment 'collaborator comment' '.author_association="COLLABORATOR"' 'QA comment is edited'
mutate_comment 'edited approval' '.updated_at="2026-10-22T01:02:04Z"' 'QA comment is edited'
mutate_comment 'invalid timestamp' '.created_at="yesterday" | .updated_at="yesterday"' 'QA comment is edited'
mutate_comment 'missing body' 'del(.body)' 'QA comment is edited'

mutate_comment 'wrong run' '.body |= sub("run_id=123456789"; "run_id=111")' 'QA approval fields do not exactly match'
mutate_comment 'retry attempt' '.body |= sub("run_attempt=1"; "run_attempt=2")' 'QA approval fields do not exactly match'
mutate_comment 'wrong source sha' '.body |= sub("source_sha=[0-9a-f]+"; "source_sha=ffffffffffffffffffffffffffffffffffffffff")' 'QA approval fields do not exactly match'
mutate_comment 'wrong build' '.body |= sub("build=3"; "build=4")' 'QA approval fields do not exactly match'
mutate_comment 'wrong version' '.body |= sub("version=0.2.0"; "version=0.2.1")' 'QA approval fields do not exactly match'
mutate_comment 'wrong archive digest' '.body |= sub("archive_sha256=[0-9a-f]+"; "archive_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")' 'QA approval fields do not exactly match'
mutate_comment 'failed QA' '.body |= sub("qa_result=pass"; "qa_result=fail")' 'QA approval fields do not exactly match'
mutate_comment 'missing QA marker' '.body |= sub("SCHNEEGLASS_ADHOC_QA_APPROVAL_V1"; "ordinary progress update")' 'QA approval fields do not exactly match'
mutate_comment 'extra text' '.body += "\nadditional comment"' 'QA approval fields do not exactly match'
mutate_comment 'repeated result key' '.body += "\nqa_result=pass"' 'QA approval fields do not exactly match'
mutate_comment 'Markdown fenced approval' '.body = ("\u0060\u0060\u0060\n") + .body + ("\n\u0060\u0060\u0060")' 'QA approval fields do not exactly match'

touch "$TMP/fail-repo"
reject 'repository API down' 'unable to fetch authenticated repository identity' verify
rm "$TMP/fail-repo"
touch "$TMP/fail-comment"
reject 'comment API down' 'unable to fetch authenticated QA comment' verify
rm "$TMP/fail-comment"

reject 'zero comment ID' 'comment ID must be positive decimal' \
  bash Scripts/verify-adhoc-qa-comment-from-github.sh 0 123456789 0.2.0 3 "$SHA" "$ARCHIVE_SHA"
reject 'injected comment ID' 'comment ID must be positive decimal' \
  bash Scripts/verify-adhoc-qa-comment-from-github.sh '1;echo unsafe' 123456789 0.2.0 3 "$SHA" "$ARCHIVE_SHA"
reject 'bad run ID' 'run ID must be positive decimal' \
  bash Scripts/verify-adhoc-qa-comment-from-github.sh 987654321 0 0.2.0 3 "$SHA" "$ARCHIVE_SHA"
reject 'invalid SHA' 'source SHA must be lowercase' \
  bash Scripts/verify-adhoc-qa-comment-from-github.sh 987654321 123456789 0.2.0 3 BAD "$ARCHIVE_SHA"
reject 'invalid digest' 'inner ZIP SHA-256 must be lowercase' \
  bash Scripts/verify-adhoc-qa-comment-from-github.sh 987654321 123456789 0.2.0 3 "$SHA" BAD
reject 'missing args' 'usage:' bash Scripts/verify-adhoc-qa-comment-from-github.sh

verify >/dev/null
echo 'Authenticated owner QA comment positive and failure fixtures passed'
