#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-history-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/commands.log"
: > "$LOG"
REAL_GREP="$(command -v grep)"

export GH_FIXTURE_ROOT="$ROOT"
export GH_FIXTURE_LOG="$LOG"
export GH_FIXTURE_STATE="$FIXTURE/state"
export GH_FIXTURE_CURRENT_MAIN_SHA='0123456789abcdef0123456789abcdef01234567'
export GH_FIXTURE_OTHER_SHA='89abcdef0123456789abcdef0123456789abcdef'
export GH_FIXTURE_MAIN_RACE_MODE='none'
export GH_FIXTURE_TAG_PROBE_MODE='absent'
export GH_FIXTURE_RELEASE_PROBE_MODE='absent'
export GH_FIXTURE_DELETE_MODE='success'
export GH_FIXTURE_GREP_MODE='normal'
export GH_FIXTURE_REAL_GREP="$REAL_GREP"
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
        if [[ "${GH_FIXTURE_MAIN_RACE_MODE:-none}" == 'advance-after-upload' \
          && -f "${GH_FIXTURE_STATE:?}/main-advanced" ]]; then
          printf '%s\n' "${GH_FIXTURE_OTHER_SHA:?}"
        else
          printf '%s\n' "${GH_FIXTURE_CURRENT_MAIN_SHA:?}"
        fi
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
    if [[ -f "${GH_FIXTURE_STATE:?}/release-tag" ]]; then
      printf '%s\trefs/tags/v0.1.0\n' '0123456789abcdef0123456789abcdef01234567'
      exit 0
    fi
    case "${GH_FIXTURE_TAG_PROBE_MODE:-absent}" in
      absent)
        exit 2
        ;;
      exists)
        printf '%s\trefs/tags/v0.1.0\n' '0123456789abcdef0123456789abcdef01234567'
        exit 0
        ;;
      failure)
        echo 'fixture: remote tag probe unavailable' >&2
        exit 42
        ;;
      failure-after-cleanup)
        if [[ -f "${GH_FIXTURE_STATE:?}/cleanup-attempted" ]]; then
          echo 'fixture: post-cleanup remote tag probe unavailable' >&2
          exit 42
        fi
        exit 2
        ;;
      exists-after-cleanup)
        if [[ -f "${GH_FIXTURE_STATE:?}/cleanup-attempted" ]]; then
          printf '%s\trefs/tags/v0.1.0\n' '0123456789abcdef0123456789abcdef01234567'
          exit 0
        fi
        exit 2
        ;;
      *)
        echo "unexpected tag probe fixture mode: ${GH_FIXTURE_TAG_PROBE_MODE:-}" >&2
        exit 91
        ;;
    esac
    ;;
  push)
    [[ "${2:-}" == '--force-with-lease=refs/tags/v0.1.0:0123456789abcdef0123456789abcdef01234567' ]]
    [[ "${3:-}" == 'origin' ]]
    [[ "${4:-}" == ':refs/tags/v0.1.0' ]]
    case "${GH_FIXTURE_TAG_DELETE_MODE:-success}" in
      success)
        rm -f "${GH_FIXTURE_STATE:?}/release-tag"
        exit 0
        ;;
      failure)
        echo 'fixture: conditional tag cleanup unavailable' >&2
        exit 42
        ;;
      *)
        echo "unexpected tag delete fixture mode: ${GH_FIXTURE_TAG_DELETE_MODE:-}" >&2
        exit 92
        ;;
    esac
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
RELEASE_PROBE_MODE="${GH_FIXTURE_RELEASE_PROBE_MODE:-absent}"
RELEASE_VERIFY_MODE="${GH_FIXTURE_RELEASE_VERIFY_MODE:-success}"
ASSET_MODE="${GH_FIXTURE_ASSET_MODE:-exact}"
CLEANUP_RACE_MODE="${GH_FIXTURE_CLEANUP_RACE_MODE:-none}"
MUTABLE_CLEANUP_RACE_MODE="${GH_FIXTURE_MUTABLE_CLEANUP_RACE_MODE:-none}"
MAIN_RACE_MODE="${GH_FIXTURE_MAIN_RACE_MODE:-none}"
printf 'gh ' >> "$LOG"
printf '%q ' "$@" >> "$LOG"
printf '\n' >> "$LOG"

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  api)
    METHOD='GET'
    ENDPOINT=''
    JQ=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --paginate|--slurp)
          shift
          ;;
        --method)
          METHOD="$2"
          shift 2
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

    if [[ "$METHOD" == 'DELETE' ]]; then
      case "$ENDPOINT" in
        repos/example/SchneeGlass/releases/101)
          touch "$STATE/cleanup-attempted"
          case "${GH_FIXTURE_DELETE_MODE:-success}" in
            success)
              rm -f "$STATE/release-created" "$STATE/release-public"
              exit 0
              ;;
            failure)
              echo 'fixture: release ID cleanup unavailable' >&2
              exit 42
              ;;
            *)
              echo "unexpected delete fixture mode: ${GH_FIXTURE_DELETE_MODE:-}" >&2
              exit 106
              ;;
          esac
          ;;
        *)
          echo "unexpected gh api delete endpoint: $ENDPOINT" >&2
          exit 107
          ;;
      esac
    fi

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
      repos/example/SchneeGlass/branches/main)
        printf '{"protected":true,"protection":{"required_status_checks":{"contexts":[],"checks":[]}}}\n'
        ;;
      repos/example/SchneeGlass/immutable-releases)
        printf '{"enabled":true}\n'
        ;;
      'repos/example/SchneeGlass/rules/branches/main?per_page=100')
        printf '%s\n' '[[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"required_review_thread_resolution":true}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368},{"context":"Compatibility / macOS 15 / App Build","integration_id":15368}],"strict_required_status_checks_policy":true}}]]'
        ;;
      'repos/example/SchneeGlass/releases?per_page=100')
        case "$JQ" in
          '.[] | select(.draft == false) | .tag_name')
            case "$HISTORY_MODE" in
              failure)
                echo 'fixture: release history API unavailable' >&2
                exit 42
                ;;
              empty)
                exit 0
                ;;
              concurrent-new-release)
                history_reads=0
                if [[ -f "$STATE/history-read-count" ]]; then
                  read -r history_reads < "$STATE/history-read-count"
                fi
                history_reads=$((history_reads + 1))
                printf '%s\n' "$history_reads" > "$STATE/history-read-count"
                if [[ "$history_reads" -eq 1 ]]; then
                  exit 0
                fi
                printf '%s\n' 'v0.0.9'
                ;;
              *)
                echo "unexpected release history fixture mode: $HISTORY_MODE" >&2
                exit 93
                ;;
            esac
            ;;
          '.[] | .tag_name')
            case "$RELEASE_PROBE_MODE" in
              absent)
                exit 0
                ;;
              exists)
                printf '%s\n' 'v0.1.0'
                ;;
              failure)
                echo 'fixture: release-name probe unavailable' >&2
                exit 42
                ;;
              failure-after-cleanup)
                if [[ -f "$STATE/cleanup-attempted" ]]; then
                  echo 'fixture: post-cleanup release-name probe unavailable' >&2
                  exit 42
                fi
                exit 0
                ;;
              exists-after-cleanup)
                if [[ -f "$STATE/cleanup-attempted" ]]; then
                  printf '%s\n' 'v0.1.0'
                fi
                exit 0
                ;;
              *)
                echo "unexpected release probe fixture mode: $RELEASE_PROBE_MODE" >&2
                exit 104
                ;;
            esac
            ;;
          *)
            echo "unexpected releases jq: $JQ" >&2
            exit 105
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
          isPrerelease)
            printf 'false\n'
            ;;
          databaseId)
            printf '101\n'
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
              mutable)
                printf 'false\n'
                if [[ "$MUTABLE_CLEANUP_RACE_MODE" == 'replace-after-immutability' && -f "$STATE/release-public" ]]; then
                  touch "$STATE/replacement-public-release"
                fi
                ;;
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
        touch "$STATE/release-tag"
        ;;
      upload)
        [[ -f "$STATE/release-created" ]]
        if [[ "$MAIN_RACE_MODE" == 'advance-after-upload' ]]; then
          touch "$STATE/main-advanced"
        fi
        ;;
      edit)
        [[ -f "$STATE/release-created" ]]
        touch "$STATE/release-public"
        ;;
      download)
        TAG="${1:-}"
        shift || true
        DIR=''
        while [[ "$#" -gt 0 ]]; do
          case "$1" in
            --repo|--pattern)
              shift 2
              ;;
            --dir)
              DIR="$2"
              shift 2
              ;;
            *)
              echo "unexpected historical release download argument: $1" >&2
              exit 98
              ;;
          esac
        done
        [[ -n "$DIR" ]] || { echo 'historical release download dir is required' >&2; exit 98; }
        if [[ "$HISTORY_MODE" == 'concurrent-new-release' && "$TAG" == 'v0.0.9' ]]; then
          mkdir -p "$DIR"
          cat > "$DIR/RELEASE_EVIDENCE.txt" <<'EOF'
schema_version=1
bundle_build=2
EOF
        else
          echo "historical release download is not expected in this fixture: $TAG" >&2
          exit 98
        fi
        ;;
      delete)
        touch "$STATE/cleanup-attempted"
        case "${GH_FIXTURE_DELETE_MODE:-success}" in
          success)
            if [[ "$MUTABLE_CLEANUP_RACE_MODE" == 'replace-after-immutability' ]]; then
              rm -f "$STATE/replacement-public-release"
            fi
            rm -f "$STATE/release-created" "$STATE/release-public" "$STATE/release-tag"
            ;;
          failure)
            echo 'fixture: mutable Draft cleanup delete unavailable' >&2
            exit 42
            ;;
          *)
            echo "unexpected delete fixture mode: ${GH_FIXTURE_DELETE_MODE:-}" >&2
            exit 106
            ;;
        esac
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

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

REAL_GREP="${GH_FIXTURE_REAL_GREP:?}"
MODE="${GH_FIXTURE_GREP_MODE:-normal}"
LAST_ARG="${!#:-}"

case "$MODE:$LAST_ARG" in
  partial-main-fetch-count-failure:*)
    printf '2\n'
    exit 42
    ;;
  failure-preexisting:*/existing-release-tags.txt)
    echo 'fixture: pre-existing Release-name membership probe unavailable' >&2
    exit 42
    ;;
  failure-after-cleanup:*/mutable-cleanup-release-tags.txt)
    echo 'fixture: post-cleanup Release-name membership probe unavailable' >&2
    exit 42
    ;;
esac

exec "$REAL_GREP" "$@"
SHIM
chmod +x "$FIXTURE/bin/grep"

assert_main_fetch_count() {
  local expected="$1"
  local count=''
  local status=0

  if count="$(grep -Fc 'git fetch origin main ' "$LOG")"; then
    status=0
  else
    status=$?
  fi

  if [[ "$status" -ne 0 ]]; then
    echo "Main-fetch count assertion failed: unable to enumerate fetches (grep status $status)" >&2
    return 1
  fi
  if [[ ! "$count" =~ ^[0-9]+$ ]]; then
    echo "Main-fetch count assertion failed: count is not numeric: $count" >&2
    return 1
  fi
  if [[ "$count" -ne "$expected" ]]; then
    echo "Main-fetch count assertion failed: expected $expected fetch(es), found $count" >&2
    return 1
  fi
}

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

# Public release history can change while the Draft is prepared. A higher build
# appearing after the initial empty-history check must be re-read and reject this
# lower candidate before Draft -> public.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='concurrent-new-release'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='exact'
export GH_FIXTURE_CLEANUP_RACE_MODE='none'
OUTPUT_HISTORY_ADVANCED="$FIXTURE/output-history-advanced-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_HISTORY_ADVANCED" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_HISTORY_ADVANCED"
  cat "$LOG"
  echo 'Release publication unexpectedly accepted a candidate after public build history advanced.' >&2
  exit 1
fi

grep -Fq 'Release build history validation failed: current build 1 must be greater than published maximum 2' "$OUTPUT_HISTORY_ADVANCED"
if grep -Fq 'gh release edit ' "$LOG"; then
  echo 'Stale build reached the Draft-to-public mutation after public history advanced.' >&2
  exit 1
fi
HISTORY_ENUMERATION_COUNT=''
HISTORY_ENUMERATION_STATUS=0
set +e
HISTORY_ENUMERATION_COUNT="$(grep -Fc 'select\(.draft\ ==\ false\)' "$LOG")"
HISTORY_ENUMERATION_STATUS=$?
set -e
[[ "$HISTORY_ENUMERATION_STATUS" -eq 0 ]] || {
  echo "Unable to count public release-history enumerations (grep status $HISTORY_ENUMERATION_STATUS)." >&2
  exit 1
}
[[ "$HISTORY_ENUMERATION_COUNT" =~ ^[0-9]+$ ]] || {
  echo "Public release-history enumeration count is not numeric: $HISTORY_ENUMERATION_COUNT" >&2
  exit 1
}
[[ "$HISTORY_ENUMERATION_COUNT" -eq 2 ]] || {
  echo "Expected two public release-history enumerations, found $HISTORY_ENUMERATION_COUNT." >&2
  exit 1
}
export GH_FIXTURE_HISTORY_MODE='empty'

# If main advances after the initial freshness check while the Draft is prepared, the
# candidate is stale at publication time. A final pre-publication check must stop before
# gh release edit and leave the run-owned Draft/tag for manual reconciliation.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_CURRENT_MAIN_SHA='0123456789abcdef0123456789abcdef01234567'
export GH_FIXTURE_MAIN_RACE_MODE='advance-after-upload'
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='exact'
export GH_FIXTURE_CLEANUP_RACE_MODE='none'
OUTPUT_MAIN_ADVANCED="$FIXTURE/output-main-advanced-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_MAIN_ADVANCED" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_MAIN_ADVANCED"
  cat "$LOG"
  echo 'Release publication unexpectedly accepted a candidate after main advanced during Draft preparation.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: candidate source commit does not match current main before publication' "$OUTPUT_MAIN_ADVANCED"
if grep -Fq 'gh release edit ' "$LOG"; then
  echo 'Stale candidate reached the publication command after main advanced during Draft preparation.' >&2
  exit 1
fi
! grep -Fq 'gh api --method DELETE' "$LOG"
! grep -Fq 'git push --force-with-lease=' "$LOG"
grep -Fq 'Release cleanup is non-destructive for v0.1.0 (release ID 101)' "$OUTPUT_MAIN_ADVANCED"
grep -Fq 'manual reconciliation required' "$OUTPUT_MAIN_ADVANCED"
if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-tag" ]]; then
  echo 'Run-owned Draft/tag did not survive final main freshness failure.' >&2
  exit 1
fi
if ! assert_main_fetch_count 2; then
  cat "$LOG"
  echo 'Publication did not fetch current main exactly twice across the initial and final freshness checks.' >&2
  exit 1
fi

# The fetch-count proof itself must fail closed if grep emits the expected count
# and then reports an enumeration failure.
export GH_FIXTURE_GREP_MODE='partial-main-fetch-count-failure'
set +e
assert_main_fetch_count 2
STATUS=$?
set -e
export GH_FIXTURE_GREP_MODE='normal'

if [[ "$STATUS" -eq 0 ]]; then
  echo 'Main-fetch count assertion unexpectedly accepted partial output from failed enumeration.' >&2
  exit 1
fi

ASSET_VIEW_LINE="$(grep -nF -- '--json assets ' "$LOG" | tail -n 1 | cut -d: -f1)"
FINAL_MAIN_FETCH_LINE="$(grep -nF 'git fetch origin main --force ' "$LOG" | tail -n 1 | cut -d: -f1)"
if [[ -z "$ASSET_VIEW_LINE" || -z "$FINAL_MAIN_FETCH_LINE" \
  || "$FINAL_MAIN_FETCH_LINE" -le "$ASSET_VIEW_LINE" ]]; then
  cat "$LOG"
  echo 'Final main re-fetch did not occur after Draft asset validation.' >&2
  exit 1
fi
export GH_FIXTURE_MAIN_RACE_MODE='none'

# A transport/configuration failure while probing the target tag is not proof that the
# tag is absent. Publication must fail closed before Draft creation.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_TAG_PROBE_MODE='failure'
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_ASSET_MODE='exact'
export GH_FIXTURE_CLEANUP_RACE_MODE='none'
OUTPUT_TAG_PROBE_FAILURE="$FIXTURE/output-tag-probe-failure.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TAG_PROBE_FAILURE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_TAG_PROBE_FAILURE"
  cat "$LOG"
  echo 'Release publication unexpectedly continued when target-tag absence could not be proven.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: unable to determine whether release tag already exists: v0.1.0' "$OUTPUT_TAG_PROBE_FAILURE"
! grep -Fq 'gh release create ' "$LOG"

# A positively observed pre-existing tag remains an immediate blocker.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_TAG_PROBE_MODE='exists'
export GH_FIXTURE_HISTORY_MODE='empty'
OUTPUT_TAG_EXISTS="$FIXTURE/output-tag-exists.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TAG_EXISTS" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_TAG_EXISTS"
  cat "$LOG"
  echo 'Release publication unexpectedly accepted a pre-existing target tag.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: release tag already exists: v0.1.0' "$OUTPUT_TAG_EXISTS"
! grep -Fq 'gh release create ' "$LOG"
export GH_FIXTURE_TAG_PROBE_MODE='absent'

# A failed GitHub Release-name probe is not proof that no Draft/public Release already
# owns the target tag. Publication must fail before Draft creation.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_RELEASE_PROBE_MODE='failure'
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_TAG_PROBE_MODE='absent'
OUTPUT_RELEASE_PROBE_FAILURE="$FIXTURE/output-release-probe-failure.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_RELEASE_PROBE_FAILURE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_RELEASE_PROBE_FAILURE"
  cat "$LOG"
  echo 'Release publication unexpectedly continued when GitHub Release absence could not be proven.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: unable to determine whether GitHub Release already exists: v0.1.0' "$OUTPUT_RELEASE_PROBE_FAILURE"
! grep -Fq 'gh release create ' "$LOG"

# A successful Release-name enumeration is not sufficient if exact membership cannot be
# evaluated. A grep/probe error must remain ambiguous and stop before Draft creation.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_RELEASE_PROBE_MODE='absent'
export GH_FIXTURE_GREP_MODE='failure-preexisting'
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_TAG_PROBE_MODE='absent'
OUTPUT_RELEASE_MATCH_PROBE_FAILURE="$FIXTURE/output-release-match-probe-failure.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_RELEASE_MATCH_PROBE_FAILURE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_RELEASE_MATCH_PROBE_FAILURE"
  cat "$LOG"
  echo 'Release publication unexpectedly continued when exact Release-name membership could not be determined.' >&2
  exit 1
fi

"$REAL_GREP" -Fq 'Release promotion failed: unable to determine whether GitHub Release already exists: v0.1.0' "$OUTPUT_RELEASE_MATCH_PROBE_FAILURE"
if "$REAL_GREP" -Fq 'gh release create ' "$LOG"; then
  cat "$LOG"
  echo 'Ambiguous Release-name membership reached Draft creation.' >&2
  exit 1
fi
export GH_FIXTURE_GREP_MODE='normal'

# An existing Draft/public GitHub Release with the target tag remains an immediate blocker.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_RELEASE_PROBE_MODE='exists'
export GH_FIXTURE_HISTORY_MODE='empty'
OUTPUT_RELEASE_EXISTS="$FIXTURE/output-release-exists.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_RELEASE_EXISTS" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_RELEASE_EXISTS"
  cat "$LOG"
  echo 'Release publication unexpectedly accepted a pre-existing GitHub Release.' >&2
  exit 1
fi

grep -Fq 'Release promotion failed: GitHub Release already exists: v0.1.0' "$OUTPUT_RELEASE_EXISTS"
! grep -Fq 'gh release create ' "$LOG"
export GH_FIXTURE_RELEASE_PROBE_MODE='absent'

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

# An unexpected Draft asset must stop publication and preserve the run-owned Draft/tag for manual reconciliation.
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
  if grep -Fq 'gh api --method DELETE' "$LOG"; then
    echo 'Draft asset mismatch reached destructive Release cleanup.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'git push --force-with-lease=' "$LOG"; then
    echo 'Draft asset mismatch reached destructive tag cleanup.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  grep -Fq 'Release cleanup is non-destructive for v0.1.0 (release ID 101)' "$OUTPUT_EXTRA_BEFORE"
  grep -Fq 'manual reconciliation required' "$OUTPUT_EXTRA_BEFORE"
  if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-tag" ]]; then
    echo 'Run-owned Draft/tag did not survive pre-publication asset mismatch.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

# Pre-publication cleanup must remain non-destructive even when a synthetic
# destructive delete path is configured to fail. That path must never be invoked.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='success'
export GH_FIXTURE_RELEASE_PROBE_MODE='absent'
export GH_FIXTURE_TAG_PROBE_MODE='absent'
export GH_FIXTURE_GREP_MODE='normal'
export GH_FIXTURE_DELETE_MODE='failure'
export GH_FIXTURE_ASSET_MODE='extra-before'
export GH_FIXTURE_CLEANUP_RACE_MODE='none'
OUTPUT_NO_DELETE="$FIXTURE/output-prepublication-no-delete.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_NO_DELETE" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_NO_DELETE"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after Draft asset mismatch.' >&2
  exit 1
fi

"$REAL_GREP" -Fq 'Release promotion failed: draft release asset set does not exactly match expected public assets' "$OUTPUT_NO_DELETE"
"$REAL_GREP" -Fq 'Release cleanup is non-destructive for v0.1.0 (release ID 101)' "$OUTPUT_NO_DELETE"
"$REAL_GREP" -Fq 'manual reconciliation required' "$OUTPUT_NO_DELETE"
if "$REAL_GREP" -Fq 'gh api --method DELETE' "$LOG"   || "$REAL_GREP" -Fq 'git push --force-with-lease=' "$LOG"; then
  cat "$LOG"
  echo 'Pre-publication failure reached destructive remote cleanup.' >&2
  exit 1
fi
if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-tag" ]]; then
  cat "$OUTPUT_NO_DELETE"
  cat "$LOG"
  echo 'Run-owned Draft/tag did not survive non-destructive pre-publication cleanup.' >&2
  exit 1
fi
export GH_FIXTURE_DELETE_MODE='success'

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
if grep -Fq 'gh release delete ' "$LOG" \
  || grep -Fq 'gh api --method DELETE -H X-GitHub-Api-Version:\ 2026-03-10 repos/example/SchneeGlass/releases/101' "$LOG"; then
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

# Post-publication mutable cleanup has the same non-atomic destructive boundary:
# after isImmutable=false is observed, the same tag can resolve to changed/replacement
# public state before tag-addressed deletion. That state must never be auto-deleted.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='mutable'
export GH_FIXTURE_RELEASE_PROBE_MODE='absent'
export GH_FIXTURE_TAG_PROBE_MODE='absent'
export GH_FIXTURE_ASSET_MODE='exact'
export GH_FIXTURE_MUTABLE_CLEANUP_RACE_MODE='replace-after-immutability'
OUTPUT_MUTABLE_RACE="$FIXTURE/output-mutable-replacement-before-delete.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_MUTABLE_RACE" 2>&1
STATUS=$?
set -e

[[ "$STATUS" -ne 0 ]]
grep -Fq 'manual reconciliation required' "$OUTPUT_MUTABLE_RACE"
grep -Fq 'v0.1.0' "$OUTPUT_MUTABLE_RACE"
grep -Fq 'release ID 101' "$OUTPUT_MUTABLE_RACE"
if grep -Fq 'gh release delete ' "$LOG"; then
  echo 'Mutable publication race reached destructive tag-addressed Release cleanup.' >&2
  exit 1
fi
if grep -Fq 'git push ' "$LOG"; then
  echo 'Mutable publication race reached destructive tag cleanup.' >&2
  exit 1
fi
if [[ ! -f "$GH_FIXTURE_STATE/replacement-public-release" || ! -f "$GH_FIXTURE_STATE/release-tag" ]]; then
  echo 'Replacement public Release/tag did not survive mutable publication recovery.' >&2
  exit 1
fi
export GH_FIXTURE_MUTABLE_CLEANUP_RACE_MODE='none'

# A plain explicit mutable result is also preserved for operator reconciliation.
: > "$LOG"
rm -rf "$GH_FIXTURE_STATE"
mkdir -p "$GH_FIXTURE_STATE"
export GH_FIXTURE_HISTORY_MODE='empty'
export GH_FIXTURE_RELEASE_VERIFY_MODE='mutable'
export GH_FIXTURE_RELEASE_PROBE_MODE='absent'
export GH_FIXTURE_TAG_PROBE_MODE='absent'
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

grep -Fq 'Release promotion failed: published release is mutable; no automatic remote cleanup was attempted; manual reconciliation required for v0.1.0 (captured release ID 101)' "$OUTPUT_MUTABLE"
! grep -Fq 'gh release delete ' "$LOG"
! grep -Fq 'gh api --method DELETE' "$LOG"
! grep -Fq 'git push ' "$LOG"
if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-public" || ! -f "$GH_FIXTURE_STATE/release-tag" ]]; then
  cat "$OUTPUT_MUTABLE"
  cat "$LOG"
  echo 'Explicitly mutable public Release/tag was not preserved for manual reconciliation.' >&2
  exit 1
fi

rm -rf "$FIXTURE"
echo 'Release history, exact asset, and post-publication verification fixtures passed'
