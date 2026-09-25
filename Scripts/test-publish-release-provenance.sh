#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-provenance-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/commands.log"
: > "$LOG"

export GH_FIXTURE_ROOT="$ROOT"
export GH_FIXTURE_LOG="$LOG"
export GH_FIXTURE_STATE="$FIXTURE/state"
export GH_FIXTURE_CANDIDATE_SHA='0123456789abcdef0123456789abcdef01234567'
export GH_FIXTURE_OTHER_SHA='89abcdef0123456789abcdef0123456789abcdef'
export GH_FIXTURE_GOVERNANCE_MODE='valid'
mkdir -p "$GH_FIXTURE_STATE"

cat > "$FIXTURE/bin/git" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

LOG="${GH_FIXTURE_LOG:?}"
STATE="${GH_FIXTURE_STATE:?}"
CANDIDATE_SHA="${GH_FIXTURE_CANDIDATE_SHA:?}"
OTHER_SHA="${GH_FIXTURE_OTHER_SHA:?}"
TAG_MODE="${GH_FIXTURE_TAG_MODE:-exact}"
printf 'git ' >> "$LOG"
printf '%q ' "$@" >> "$LOG"
printf '\n' >> "$LOG"

case "${1:-}" in
  rev-parse)
    case "${2:-}" in
      --show-toplevel)
        printf '%s\n' "${GH_FIXTURE_ROOT:?}"
        ;;
      origin/main)
        printf '%s\n' "$CANDIDATE_SHA"
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
    if [[ -f "$STATE/release-public" ]]; then
      case "$TAG_MODE" in
        exact) printf '%s\trefs/tags/v0.1.0\n' "$CANDIDATE_SHA" ;;
        mismatch) printf '%s\trefs/tags/v0.1.0\n' "$OTHER_SHA" ;;
        *) echo "unexpected tag fixture mode: $TAG_MODE" >&2; exit 103 ;;
      esac
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
CANDIDATE_SHA="${GH_FIXTURE_CANDIDATE_SHA:?}"
OTHER_SHA="${GH_FIXTURE_OTHER_SHA:?}"
TARGET_MODE="${GH_FIXTURE_TARGET_MODE:-exact}"
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
          .head_sha) printf '%s\n' "$CANDIDATE_SHA" ;;
          *) echo "unexpected run jq: $JQ" >&2; exit 92 ;;
        esac
        ;;
      'repos/example/SchneeGlass/releases?per_page=100')
        exit 0
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
    cat > "$DIR/RELEASE_EVIDENCE.txt" <<EOF
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
commit_sha=$CANDIDATE_SHA
EOF
    ;;

  release)
    SUBCOMMAND="${1:-}"
    shift || true
    case "$SUBCOMMAND" in
      view)
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
          targetCommitish)
            if [[ "$TARGET_MODE" == 'change-after' && -f "$STATE/release-public" ]]; then
              printf '%s\n' "$OTHER_SHA"
            else
              printf '%s\n' "$CANDIDATE_SHA"
            fi
            ;;
          assets)
            printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
            ;;
          isImmutable)
            if [[ -f "$STATE/release-public" ]]; then printf 'true\n'; else printf 'false\n'; fi
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
      delete)
        rm -f "$STATE/release-created" "$STATE/release-public"
        ;;
      download)
        echo 'historical release download is not expected in this fixture' >&2
        exit 98
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

reset_case() {
  : > "$LOG"
  rm -rf "$GH_FIXTURE_STATE" "$RUNNER_TEMP"
  mkdir -p "$GH_FIXTURE_STATE" "$RUNNER_TEMP"
}

FAILURES=0

# Control: unchanged target and exact tag commit remains a valid publication.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
OUTPUT_EXACT="$FIXTURE/output-exact.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_EXACT" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -ne 0 ]]; then
  cat "$OUTPUT_EXACT"
  cat "$LOG"
  echo 'Exact release provenance fixture unexpectedly failed.' >&2
  FAILURES=$((FAILURES + 1))
fi

# Governance can drift while Draft preparation is in progress even when current main
# remains unchanged. Publication must re-read governance immediately before Draft -> public.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_GOVERNANCE_MODE='drift-before-publication'
OUTPUT_GOVERNANCE_DRIFT="$FIXTURE/output-governance-drift.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_GOVERNANCE_DRIFT" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_GOVERNANCE_DRIFT"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after release governance drifted.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: current release governance is no longer valid before publication' "$OUTPUT_GOVERNANCE_DRIFT"; then
    cat "$OUTPUT_GOVERNANCE_DRIFT"
    echo 'Governance drift did not fail with the expected final-certification error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Governance drift reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi
export GH_FIXTURE_GOVERNANCE_MODE='valid'

# The Draft target can be correct and still change after publication. The final public
# provenance must be re-read and a mismatch must fail without destructive cleanup.
reset_case
export GH_FIXTURE_TARGET_MODE='change-after'
export GH_FIXTURE_TAG_MODE='exact'
OUTPUT_TARGET_CHANGED="$FIXTURE/output-target-changed.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TARGET_CHANGED" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_TARGET_CHANGED"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after the public target commit changed.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: published release target does not match candidate source commit; publication state is ambiguous and requires manual reconciliation' "$OUTPUT_TARGET_CHANGED"; then
    cat "$OUTPUT_TARGET_CHANGED"
    echo 'Published target mismatch did not fail with the expected provenance error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release delete ' "$LOG"; then
    echo 'Published target mismatch triggered destructive release cleanup.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-public" ]]; then
    echo 'Published release state was removed after target provenance became ambiguous.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

# Even with an unchanged Release target, the actual remote tag must resolve to the exact
# candidate commit. A different tag commit is ambiguous after publication and must remain.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='mismatch'
OUTPUT_TAG_MISMATCH="$FIXTURE/output-tag-mismatch.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TAG_MISMATCH" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_TAG_MISMATCH"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded with a tag pointing at another commit.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: published release tag does not resolve to candidate source commit; publication state is ambiguous and requires manual reconciliation' "$OUTPUT_TAG_MISMATCH"; then
    cat "$OUTPUT_TAG_MISMATCH"
    echo 'Published tag mismatch did not fail with the expected provenance error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release delete ' "$LOG"; then
    echo 'Published tag mismatch triggered destructive release cleanup.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if [[ ! -f "$GH_FIXTURE_STATE/release-created" || ! -f "$GH_FIXTURE_STATE/release-public" ]]; then
    echo 'Published release state was removed after tag provenance became ambiguous.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

if [[ "$FAILURES" -ne 0 ]]; then
  echo "$FAILURES final release provenance fixture case(s) failed." >&2
  exit 1
fi

rm -rf "$FIXTURE"
echo 'Final release provenance fixtures passed'
