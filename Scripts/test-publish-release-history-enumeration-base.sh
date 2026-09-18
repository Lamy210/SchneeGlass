#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-history-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/commands.log"
: > "$LOG"

export GH_FIXTURE_ROOT="$ROOT"
export GH_FIXTURE_LOG="$LOG"
export GH_FIXTURE_STATE="$FIXTURE/state"
export GH_FIXTURE_CURRENT_MAIN_SHA='0123456789abcdef0123456789abcdef01234567'
mkdir -p "$GH_FIXTURE_STATE"

cat > "$FIXTURE/bin/git" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
printf 'git ' >> "${GH_FIXTURE_LOG:?}"
printf '%q ' "$@" >> "$GH_FIXTURE_LOG"
printf '\n' >> "$GH_FIXTURE_LOG"

case "${1:-}" in
  rev-parse)
    case "${2:-}" in
      --show-toplevel)
        printf '%s\n' "${GH_FIXTURE_ROOT:?}"
        ;;
      origin/main)
        printf '%s\n' "${GH_FIXTURE_CURRENT_MAIN_SHA:?}"
        ;;
      *)
        echo "unexpected git rev-parse argument: ${2:-}" >&2
        exit 89
        ;;
    esac
    ;;
  fetch)
    exit 0
    ;;
  cat-file)
    exit 0
    ;;
  merge-base)
    exit 0
    ;;
  ls-remote)
    if [[ -f "${GH_FIXTURE_STATE:?}/release-public" ]]; then
      printf '%s\trefs/tags/v0.1.0\n' '0123456789abcdef0123456789abcdef01234567'
      exit 0
    fi
    exit 2
    ;;
  push)
    exit 0
    ;;
  *)
    echo "unexpected git command: $*" >&2
    exit 90
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/git"

cat > "$FIXTURE/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

LOG="${GH_FIXTURE_LOG:?}"
STATE="${GH_FIXTURE_STATE:?}"
HISTORY_MODE="${GH_FIXTURE_HISTORY_MODE:-failure}"
RELEASE_VERIFY_MODE="${GH_FIXTURE_RELEASE_VERIFY_MODE:-success}"
ASSET_MODE="${GH_FIXTURE_ASSET_MODE:-exact}"
CLEANUP_RACE_MODE="${GH_FIXTURE_CLEANUP_RACE_MODE:-none}"
printf 'gh ' >> "$LOG"
printf '%q ' "$@" >> "$LOG"
printf '\n' >> "$LOG"

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  api)
    ENDPOINT=''
    JQ=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --paginate)
          shift
          ;;
        --jq)
          JQ="$2"
          shift 2
          ;;
        -H|--header)
          shift 2
          ;;
        *)
          [[ -z "$ENDPOINT" ]] || { echo "unexpected gh api argument: $1" >&2; exit 91; }
          ENDPOINT="$1"
          shift
          ;;
      esac
    done

    case "$ENDPOINT" in
      repos/example/SchneeGlass/actions/runs/123)
        case "$JQ" in
          .name) printf '%s\n' 'Production Release Candidate' ;;
          .path) printf '%s\n' '.github/workflows/production-release.yml' ;;
          .event) printf '%s\n' 'workflow_dispatch' ;;
          .status) printf '%s\n' 'completed' ;;
          .conclusion) printf '%s\n' 'success' ;;
          .head_branch) printf '%s\n' 'main' ;;
          .head_sha) printf '%s\n' '0123456789abcdef0123456789abcdef01234567' ;;
          *) echo "unexpected run jq: $JQ" >&2; exit 92 ;;
        esac
        ;;
      'repos/example/SchneeGlass/releases?per_page=100')
        case "$HISTORY_MODE" in
          failure)
            echo 'fixture: release history API unavailable' >&2
            exit 42
            ;;
          empty)
            exit 0
            ;;
          *)
            echo "unexpected release history fixture mode: $HISTORY_MODE" >&2
            exit 93
            ;;
        esac
        ;;
      *)
        echo "unexpected gh api endpoint: $ENDPOINT" >&2
        exit 94
        ;;
    esac
    ;;

  run)
    [[ "${1:-}" == 'download' ]]
    shift
    [[ "${1:-}" == '123' ]]
    shift
    DIR=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repo|--name)
          shift 2
          ;;
        --dir)
          DIR="$2"
          shift 2
          ;;
        *)
          echo "unexpected gh run download argument: $1" >&2
          exit 95
          ;;
      esac
    done
    [[ -n "$DIR" ]]
    mkdir -p "$DIR"
    printf 'signed candidate fixture\n' > "$DIR/SchneeGlass-0.1.0.zip"
    HASH="$(shasum -a 256 "$DIR/SchneeGlass-0.1.0.zip" | awk '{print $1}')"
    printf '%s  %s\n' "$HASH" 'SchneeGlass-0.1.0.zip' > "$DIR/SHA256SUMS"
    cat > "$DIR/RELEASE_EVIDENCE.txt" <<'EOF'
schema_version=1
version=0.1.0
notarization_id=00000000-0000-0000-0000-000000000000
notarization_status=Accepted
codesign=verified
stapler=validated
gatekeeper=accepted
bundle_identifier=io.github.lamy210.schneeglass
bundle_version=0.1.0
bundle_build=1
commit_sha=0123456789abcdef0123456789abcdef01234567
EOF
    ;;

  release)
    SUBCOMMAND="${1:-}"
    shift || true
    case "$SUBCOMMAND" in
      view)
        TAG="${1:-}"
        shift || true
        if [[ ! -f "$STATE/release-created" ]]; then
          exit 1
        fi
        JSON=''
        while [[ "$#" -gt 0 ]]; do
          case "$1" in
            --repo)
              shift 2
              ;;
            --json)
              JSON="$2"
              shift 2
              ;;
            --jq)
              shift 2
              ;;
            *)
              echo "unexpected release view argument: $1" >&2
              exit 96
              ;;
          esac
        done
        case "$JSON" in
          '') exit 0 ;;
          isDraft)
            if [[ -f "$STATE/release-public" ]]; then printf 'false\n'; else printf 'true\n'; fi
            ;;
          targetCommitish) printf '%s\n' '0123456789abcdef0123456789abcdef01234567' ;;
          assets)
            case "$ASSET_MODE" in
              exact)
                printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
                ;;
              extra-before)
                if [[ "$CLEANUP_RACE_MODE" == 'external-public-before-asset-mismatch' ]]; then
                  touch "$STATE/release-public"
                fi
                printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt' 'unexpected.txt'
                ;;
              extra-after)
                printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
                if [[ -f "$STATE/release-public" ]]; then
                  printf '%s\n' 'unexpected.txt'
                fi
                ;;
              *)
                echo "unexpected asset fixture mode: $ASSET_MODE" >&2
                exit 102
                ;;
            esac
            ;;
          isImmutable)
            case "$RELEASE_VERIFY_MODE" in
              success)
                if [[ -f "$STATE/release-public" ]]; then printf 'true\n'; else printf 'false\n'; fi
                ;;
              mutable) printf 'false\n' ;;
              failure)
                if [[ -f "$STATE/release-public" ]]; then
                  echo 'fixture: published release immutability read unavailable' >&2
                  exit 42
                fi
                printf 'false\n'
                ;;
              *)
                echo "unexpected release verification fixture mode: $RELEASE_VERIFY_MODE" >&2
                exit 101
                ;;
            esac
            ;;
          *) echo "unexpected release view json field: $JSON" >&2; exit 97 ;;
        esac
        ;;
      create)
        touch "$STATE/release-created"
        ;;
      upload)
        [[ -f "$STATE/release-created" ]]
        ;;
      edit)
        [[ -f "$STATE/release-created" ]]
        touch "$STATE/release-public"
        ;;
      download)
        echo 'historical release download is not expected in this fixture' >&2
        exit 98
        ;;
      delete)
        rm -f "$STATE/release-created" "$STATE/release-public"
        ;;
      *)
        echo "unexpected gh release subcommand: $SUBCOMMAND" >&2
        exit 99
        ;;
    esac
    ;;

  *)
    echo "unexpected gh command: $COMMAND $*" >&2
    exit 100
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/gh"

export PATH="$FIXTURE/bin:$PATH"
export RELEASE_VERSION='0.1.0'
export CANDIDATE_RUN_ID='123'
export GITHUB_REPOSITORY='example/SchneeGlass'
export GITHUB_REF='refs/heads/main'
export GH_TOKEN='fixture-token'
export CONFIRM_MANUAL_QA='true'
export CONFIRM_IMMUTABLE_RELEASES='true'
export CONFIRM_RELEASE_GOVERNANCE='true'
export CONFIRM_PUBLISH='true'
export RUNNER_TEMP="$FIXTURE/runner-temp"
mkdir -p "$RUNNER_TEMP"

# Enumeration failure must stop publication before any release/tag creation.
export GH_FIXTURE_HISTORY_MODE='failure'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='exact'
export GH_FIXTURE_CLEANUP_RACE_MODE='none'
OUTPUT="$FIXTURE/output-failure.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Release publication unexpectedly succeeded after release-history enumeration failed.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: failed to enumerate public release history' "$OUTPUT"
! grep -Fq 'gh release create ' "$LOG"

# A successful enumeration with zero public releases is still the valid first-release path.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_EMPTY="$FIXTURE/output-empty.log"
bash Scripts/publish-notarized-release.sh >"$OUTPUT_EMPTY" 2>&1

grep -Fq 'Release build history OK: first public release, current build=1' "$OUTPUT_EMPTY"
grep -Fq 'Published immutable release v0.1.0 from candidate run 123' "$OUTPUT_EMPTY"
grep -Fq 'gh release create ' "$LOG"

# A candidate that is only an ancestor of current main is stale. Publication must stop
# before creating a tag/Release even when the candidate run and artifact are otherwise valid.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_CURRENT_MAIN_SHA='89abcdef0123456789abcdef0123456789abcdef'
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='exact'
export GH_FIXTURE_CLEANUP_RACE_MODE='none'
OUTPUT_STALE="$FIXTURE/output-stale-candidate.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_STALE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_STALE"
  cat "$LOG"
  echo 'Release publication unexpectedly accepted a stale candidate ancestor of current main.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: candidate source commit does not match current main' "$OUTPUT_STALE"
! grep -Fq 'gh release create ' "$LOG"
export GH_FIXTURE_CURRENT_MAIN_SHA='0123456789abcdef0123456789abcdef01234567'

# An unexpected Draft asset must stop publication and clean up the run-owned Draft.
FAILURES=0
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='extra-before'
OUTPUT_EXTRA_BEFORE="$FIXTURE/output-extra-before.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_EXTRA_BEFORE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_EXTRA_BEFORE"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded with an extra Draft asset.' >&2
  FAILURES=$((FAILURES + 1))
else
  grep -Fq 'Release promotion failed: draft release asset set does not exactly match expected public assets' "$OUTPUT_EXTRA_BEFORE"
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Draft asset mismatch reached the publication command.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if ! grep -Fq 'gh release delete ' "$LOG"; then
    echo 'Run-owned Draft was not cleaned up after a pre-publication asset mismatch.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

# If the run-owned Draft becomes public before a pre-publication failure and the
# immutability read is unavailable, cleanup ownership is ambiguous. The trap must preserve
# the Release/tag instead of deleting based on absence of an immutable=true proof.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='failure'
export GH_FIXTURE_ASSET_MODE='extra-before'
export GH_FIXTURE_CLEANUP_RACE_MODE='external-public-before-asset-mismatch'
OUTPUT_CLEANUP_AMBIGUOUS="$FIXTURE/output-cleanup-ambiguous.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_CLEANUP_AMBIGUOUS" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_CLEANUP_AMBIGUOUS"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after the pre-publication state changed.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: draft release asset set does not exactly match expected public assets' "$OUTPUT_CLEANUP_AMBIGUOUS"
if grep -Fq 'gh release delete ' "$LOG"; then
  cat "$OUTPUT_CLEANUP_AMBIGUOUS"
  cat "$LOG"
  echo 'Ambiguous pre-publication cleanup state triggered destructive release cleanup.' >&2
  exit 1
fi
if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-public" ]]; then
  cat "$OUTPUT_CLEANUP_AMBIGUOUS"
  cat "$LOG"
  echo 'Ambiguous pre-publication release state was removed instead of preserved.' >&2
  exit 1
fi

# A release that gains an extra asset only after publication is ambiguous. The run must
# fail without destructively deleting a release/tag that may already be immutable.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='extra-after'
export GH_FIXTURE_CLEANUP_RACE_MODE='none'
OUTPUT_EXTRA_AFTER="$FIXTURE/output-extra-after.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_EXTRA_AFTER" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_EXTRA_AFTER"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after the public asset set changed.' >&2
  FAILURES=$((FAILURES + 1))
else
  grep -Fq 'Release promotion failed: published release asset set does not exactly match expected public assets; publication state is ambiguous and requires manual reconciliation' "$OUTPUT_EXTRA_AFTER"
  if grep -Fq 'gh release delete ' "$LOG"; then
    echo 'Post-publication asset mismatch triggered destructive release cleanup.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-public" ]]; then
    echo 'Published release state was removed after the public asset set became ambiguous.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES exact release asset fixture case(s) failed." >&2
  exit 1
fi

# Once publication succeeds, an unavailable immutability read is ambiguous. It must not
# trigger destructive cleanup of a release/tag that may already be public and immutable.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='failure'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_AMBIGUOUS="$FIXTURE/output-post-publication-verification-failure.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_AMBIGUOUS" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_AMBIGUOUS"
  echo 'Release publication unexpectedly reported success when immutability could not be verified.' >&2
  exit 1
fi

if grep -Fq 'gh release delete ' "$LOG"; then
  cat "$OUTPUT_AMBIGUOUS"
  cat "$LOG"
  echo 'Post-publication verification failure triggered destructive release cleanup.' >&2
  exit 1
fi

if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-public" ]]; then
  cat "$OUTPUT_AMBIGUOUS"
  cat "$LOG"
  echo 'Published release state was removed after verification became unavailable.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: unable to verify published release immutability; publication state is ambiguous and requires manual reconciliation' "$OUTPUT_AMBIGUOUS"

# An explicit mutable result remains safely auto-cleaned, preserving the existing fail-closed contract.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='mutable'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_MUTABLE="$FIXTURE/output-mutable.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_MUTABLE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_MUTABLE"
  echo 'Release publication unexpectedly reported success for an explicitly mutable release.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: published release was not immutable and was removed; enable repository release immutability before retrying' "$OUTPUT_MUTABLE"
grep -Fq 'gh release delete ' "$LOG"
if [[ -f "$GH_FIXTURE_STATE/release-created" || -f "$GH_FIXTURE_STATE/release-public" ]]; then
  cat "$OUTPUT_MUTABLE"
  cat "$LOG"
  echo 'Explicitly mutable release was not removed.' >&2
  exit 1
fi

rm -rf "$FIXTURE"
echo 'Release history, exact asset, and post-publication verification fixtures passed'
