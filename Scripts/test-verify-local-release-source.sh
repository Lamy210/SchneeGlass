#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-local-release-source-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin" "$FIXTURE/repo"

VALID_SHA='0123456789abcdef0123456789abcdef01234567'
OTHER_SHA='89abcdef0123456789abcdef0123456789abcdef'

cat > "$FIXTURE/bin/git-fixture" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${LOCAL_SOURCE_FIXTURE_GIT_FAIL:-}" == "$*" ]]; then
  exit 42
fi

case "$*" in
  'rev-parse --show-toplevel')
    printf '%s\n' "${LOCAL_SOURCE_FIXTURE_ROOT:?}"
    ;;
  'branch --show-current')
    printf '%s\n' "${LOCAL_SOURCE_FIXTURE_BRANCH:-main}"
    ;;
  'rev-parse HEAD')
    printf '%s\n' "${LOCAL_SOURCE_FIXTURE_LOCAL_SHA:?}"
    ;;
  'status --porcelain=v1 --untracked-files=normal')
    if [[ -n "${LOCAL_SOURCE_FIXTURE_DIRTY:-}" ]]; then
      printf '%s\n' ' M .github/rulesets/main-release-governance.json'
    fi
    ;;
  *)
    echo "unexpected git command: $*" >&2
    exit 90
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/git-fixture"

cat > "$FIXTURE/bin/gh-fixture" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == 'auth' && "${2:-}" == 'status' ]]; then
  exit 0
fi

if [[ "${1:-}" == 'api' && "${2:-}" == 'repos/example/SchneeGlass/branches/main' ]]; then
  if [[ -n "${LOCAL_SOURCE_FIXTURE_GH_FAIL:-}" ]]; then
    exit 42
  fi
  if [[ -n "${LOCAL_SOURCE_FIXTURE_MALFORMED_REMOTE:-}" ]]; then
    printf '%s\n' '{"name":"main","commit":{"sha":"not-a-sha"}}'
  else
    printf '{"name":"main","commit":{"sha":"%s"}}\n' "${LOCAL_SOURCE_FIXTURE_REMOTE_SHA:?}"
  fi
  exit 0
fi

echo "unexpected gh command: $*" >&2
exit 91
SHIM
chmod +x "$FIXTURE/bin/gh-fixture"

export GIT_BIN="$FIXTURE/bin/git-fixture"
export GH_BIN="$FIXTURE/bin/gh-fixture"
export LOCAL_SOURCE_FIXTURE_ROOT="$FIXTURE/repo"
export LOCAL_SOURCE_FIXTURE_LOCAL_SHA="$VALID_SHA"
export LOCAL_SOURCE_FIXTURE_REMOTE_SHA="$VALID_SHA"

bash Scripts/verify-local-release-source.sh example/SchneeGlass

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$FIXTURE/failure.log" 2>&1; then
    cat "$FIXTURE/failure.log"
    echo "Local release source verifier unexpectedly accepted: $label" >&2
    exit 1
  fi
}

expect_failure \
  'non-main branch' \
  env LOCAL_SOURCE_FIXTURE_BRANCH='feature/stale' \
    bash Scripts/verify-local-release-source.sh example/SchneeGlass
grep -Fq 'current branch must be main' "$FIXTURE/failure.log"

expect_failure \
  'stale local HEAD' \
  env LOCAL_SOURCE_FIXTURE_REMOTE_SHA="$OTHER_SHA" \
    bash Scripts/verify-local-release-source.sh example/SchneeGlass
grep -Fq 'local HEAD does not match live remote main' "$FIXTURE/failure.log"

expect_failure \
  'dirty working tree' \
  env LOCAL_SOURCE_FIXTURE_DIRTY=1 \
    bash Scripts/verify-local-release-source.sh example/SchneeGlass
grep -Fq 'working tree must be clean' "$FIXTURE/failure.log"

expect_failure \
  'malformed local HEAD' \
  env LOCAL_SOURCE_FIXTURE_LOCAL_SHA='deadbeef' \
    bash Scripts/verify-local-release-source.sh example/SchneeGlass
grep -Fq 'local HEAD must be a lowercase 40-hex commit' "$FIXTURE/failure.log"

expect_failure \
  'malformed remote response' \
  env LOCAL_SOURCE_FIXTURE_MALFORMED_REMOTE=1 \
    bash Scripts/verify-local-release-source.sh example/SchneeGlass
grep -Fq 'remote main branch response is malformed' "$FIXTURE/failure.log"

expect_failure \
  'git working tree probe failure' \
  env LOCAL_SOURCE_FIXTURE_GIT_FAIL='status --porcelain=v1 --untracked-files=normal' \
    bash Scripts/verify-local-release-source.sh example/SchneeGlass
grep -Fq 'working tree probe failed (git status 42)' "$FIXTURE/failure.log"

expect_failure \
  'GitHub branch API failure' \
  env LOCAL_SOURCE_FIXTURE_GH_FAIL=1 \
    bash Scripts/verify-local-release-source.sh example/SchneeGlass

rm -rf "$FIXTURE"
echo 'Local release source fixtures passed'
