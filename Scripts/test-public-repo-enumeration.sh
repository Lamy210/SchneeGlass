#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-public-repo-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
REAL_GIT="$(command -v git)"
REAL_GREP="$(command -v grep)"
ORIGINAL_PATH="$PATH"
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

# Exercise the real git grep command in an isolated repository so the high-confidence
# secret regex cannot silently become an invalid option again. Build the synthetic token
# from pieces so this fixture source itself never contains a matching token.
SYNTHETIC_REPO="$FIXTURE/synthetic-repo"
mkdir -p "$SYNTHETIC_REPO"
(
  cd "$SYNTHETIC_REPO"
  "$REAL_GIT" init -q
  printf 'synthetic=%s%s\n' 'gh' 'p_aaaaaaaaaaaaaaaaaaaa' > secret.txt
  printf 'EXAMPLE_ONLY=1\n' > .env.example
  "$REAL_GIT" add secret.txt .env.example

  set +e
  PATH="$ORIGINAL_PATH" bash "$ROOT/Scripts/verify-public-repo.sh" >"$FIXTURE/secret-detection.log" 2>&1
  status=$?
  set -e

  if [[ "$status" -eq 0 ]]; then
    cat "$FIXTURE/secret-detection.log"
    echo 'Public Repository Guard unexpectedly accepted a synthetic high-confidence secret pattern.' >&2
    exit 1
  fi

  "$REAL_GREP" -Fq \
    'Public repository violation: high-confidence secret pattern detected.' \
    "$FIXTURE/secret-detection.log"

  rm -f secret.txt
  "$REAL_GIT" rm --cached -q secret.txt

  PATH="$ORIGINAL_PATH" bash "$ROOT/Scripts/verify-public-repo.sh" >"$FIXTURE/env-example.log" 2>&1
)

rm -rf "$FIXTURE"
echo 'Public Repository Guard enumeration and detection fixtures passed'
