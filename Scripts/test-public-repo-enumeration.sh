#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-public-repo-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
REAL_GIT="$(command -v git)"
REAL_GREP="$(command -v grep)"
export PUBLIC_REPO_FIXTURE_REAL_GIT="$REAL_GIT"

cat > "$FIXTURE/bin/git" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

MODE="${PUBLIC_REPO_FIXTURE_MODE:?}"
REAL_GIT="${PUBLIC_REPO_FIXTURE_REAL_GIT:?}"

case "${1:-}" in
  rev-parse)
    exec "$REAL_GIT" "$@"
    ;;
  ls-files)
    if [[ "$MODE" == 'ls-files-failure' ]]; then
      echo 'fixture: git ls-files unavailable' >&2
      exit 42
    fi
    exec "$REAL_GIT" "$@"
    ;;
  grep)
    if [[ "$MODE" == 'git-grep-failure' ]]; then
      echo 'fixture: git grep unavailable' >&2
      exit 43
    fi
    exec "$REAL_GIT" "$@"
    ;;
  *)
    exec "$REAL_GIT" "$@"
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/git"

run_failure_case() {
  local mode="$1"
  local expected="$2"
  local output="$FIXTURE/$mode.log"
  local status

  set +e
  PUBLIC_REPO_FIXTURE_MODE="$mode" \
    PATH="$FIXTURE/bin:$PATH" \
    bash Scripts/verify-public-repo.sh >"$output" 2>&1
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    cat "$output"
    echo "Public Repository Guard unexpectedly passed for fixture mode: $mode" >&2
    exit 1
  fi

  "$REAL_GREP" -Fq "$expected" "$output"
}

run_failure_case \
  'ls-files-failure' \
  'Public repository verification failed: unable to enumerate tracked repository files'

run_failure_case \
  'git-grep-failure' \
  'Public repository verification failed: unable to scan repository content for secret patterns'

rm -rf "$FIXTURE"
echo 'Public Repository Guard enumeration failure fixtures passed'
