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
    if [[ -f "$STATE/release-created" ]]; then
      case "$TAG_MODE" in
        exact)
          printf '%s\trefs/tags/v0.1.0\n' "$CANDIDATE_SHA"
          ;;
        retarget-before-publication)
          printf '%s\trefs/tags/v0.1.0\n' "$OTHER_SHA"
          ;;
        missing-before-publication)
          exit 2
          ;;
        ambiguous-before-publication)
          printf '%s\trefs/tags/v0.1.0\n' "$CANDIDATE_SHA"
          printf '%s\trefs/tags/v0.1.0\n' "$OTHER_SHA"
          ;;
        malformed-before-publication)
          printf 'not-a-sha\trefs/tags/v0.1.0\n'
          ;;
        mismatch-after-publication)
          if [[ -f "$STATE/release-public" ]]; then
            printf '%s\trefs/tags/v0.1.0\n' "$OTHER_SHA"
          else
            printf '%s\trefs/tags/v0.1.0\n' "$CANDIDATE_SHA"
          fi
          ;;
        *)
          echo "unexpected tag fixture mode: $TAG_MODE" >&2
          exit 103
          ;;
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
DRAFT_MODE="${GH_FIXTURE_DRAFT_MODE:-exact}"
PRERELEASE_MODE="${GH_FIXTURE_PRERELEASE_MODE:-stable}"
IDENTITY_MODE="${GH_FIXTURE_IDENTITY_MODE:-stable}"
ASSET_MODE="${GH_FIXTURE_ASSET_MODE:-exact}"
IMMUTABILITY_MODE="${GH_FIXTURE_IMMUTABILITY_MODE:-enabled}"
GOVERNANCE_MODE="${GH_FIXTURE_GOVERNANCE_MODE:-valid}"
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
        --paginate|--slurp)
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
      repos/example/SchneeGlass/branches/main)
        if [[ "$GOVERNANCE_MODE" == 'drift-before-publication' ]]; then
          printf '{"protected":false,"protection":{"required_status_checks":{"contexts":[],"checks":[]}}}\n'
        else
          printf '{"protected":true,"protection":{"required_status_checks":{"contexts":[],"checks":[]}}}\n'
        fi
        ;;
      'repos/example/SchneeGlass/rules/branches/main?per_page=100')
        printf '%s\n' '[[{"type":"deletion"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"required_review_thread_resolution":true}},{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"Canonical / Xcode 26.6 / App Build / Safety Guards","integration_id":15368},{"context":"Compatibility / macOS 15 / App Build","integration_id":15368}],"strict_required_status_checks_policy":true}}]]'
        ;;
      repos/example/SchneeGlass/immutable-releases)
        case "$IMMUTABILITY_MODE" in
          enabled)
            printf '{"enabled":true}\n'
            ;;
          disabled)
            printf '{"enabled":false}\n'
            ;;
          malformed)
            printf '{"enabled":"true"}\n'
            ;;
          query-failure)
            printf '{"enabled":true}\n'
            exit 42
            ;;
          *)
            echo "unexpected immutability fixture mode: $IMMUTABILITY_MODE" >&2
            exit 105
            ;;
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
            draft_reads="$(awk '/--json isDraft/ { count += 1 } END { print count + 0 }' "$LOG")"
            if [[ "$IDENTITY_MODE" == 'replace-after-cleanup-identity' && "$ASSET_MODE" == 'extra-before-publication' && "$draft_reads" -ge 2 ]]; then
              printf '202\n' > "$STATE/release-id"
            fi
            if [[ "$DRAFT_MODE" == 'query-failure-before-publication' && "$draft_reads" -ge 2 ]]; then
              printf 'true\n'
              exit 42
            elif [[ "$DRAFT_MODE" == 'invalid-before-publication' && "$draft_reads" -ge 2 ]]; then
              printf 'unknown\n'
            elif [[ -f "$STATE/release-public" ]]; then
              printf 'false\n'
            else
              printf 'true\n'
            fi
            ;;
          isPrerelease)
            case "$PRERELEASE_MODE" in
              stable)
                printf 'false\n'
                ;;
              change-before-publication)
                if [[ -f "$STATE/release-prerelease" ]]; then printf 'true\n'; else printf 'false\n'; fi
                ;;
              change-after-final-check)
                printf 'false\n'
                touch "$STATE/release-prerelease"
                ;;
              query-failure-before-publication)
                printf 'false\n'
                exit 42
                ;;
              malformed-before-publication)
                printf 'unknown\n'
                ;;
              *)
                echo "unexpected prerelease fixture mode: $PRERELEASE_MODE" >&2
                exit 106
                ;;
            esac
            ;;
          databaseId)
            identity_reads="$(awk '/--json databaseId/ { count += 1 } END { print count + 0 }' "$LOG")"
            case "$IDENTITY_MODE" in
              cleanup-query-failure)
                if [[ "$identity_reads" -ge 2 ]]; then
                  printf '101\n'
                  exit 42
                fi
                ;;
              cleanup-malformed)
                if [[ "$identity_reads" -ge 2 ]]; then
                  printf 'not-an-id\n'
                  exit 0
                fi
                ;;
              query-failure-before-publication)
                if [[ "$identity_reads" -eq 2 ]]; then
                  printf '101\n'
                  exit 42
                fi
                ;;
              malformed-before-publication)
                if [[ "$identity_reads" -eq 2 ]]; then
                  printf 'not-an-id\n'
                  exit 0
                fi
                ;;
            esac
            if [[ -f "$STATE/release-id" ]]; then
              cat "$STATE/release-id"
            else
              printf '101\n'
            fi
            ;;
          targetCommitish)
            target_reads="$(awk '/--json targetCommitish/ { count += 1 } END { print count + 0 }' "$LOG")"
            if [[ "$TARGET_MODE" == 'query-failure-before-publication' && "$target_reads" -ge 2 ]]; then
              printf '%s\n' "$CANDIDATE_SHA"
              exit 42
            elif [[ "$TARGET_MODE" == 'malformed-before-publication' && "$target_reads" -ge 2 ]]; then
              printf 'main\n'
            elif [[ "$TARGET_MODE" == 'change-before-publication' && "$target_reads" -ge 2 ]]; then
              printf '%s\n' "$OTHER_SHA"
            elif [[ "$TARGET_MODE" == 'change-after' && -f "$STATE/release-public" ]]; then
              printf '%s\n' "$OTHER_SHA"
            else
              printf '%s\n' "$CANDIDATE_SHA"
            fi
            ;;
          assets)
            asset_reads="$(grep -Fc -- '--json assets' "$LOG")"
            case "$ASSET_MODE" in
              exact)
                printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
                if [[ "$DRAFT_MODE" == 'publish-before-publication' && "$asset_reads" -ge 2 ]]; then
                  touch "$STATE/release-public"
                fi
                if [[ "$PRERELEASE_MODE" == 'change-before-publication' && "$asset_reads" -ge 2 ]]; then
                  touch "$STATE/release-prerelease"
                fi
                if [[ "$IDENTITY_MODE" == 'replace-before-publication' && "$asset_reads" -ge 2 ]]; then
                  printf '202\n' > "$STATE/release-id"
                fi
                ;;
              missing-before-publication)
                if [[ "$asset_reads" -le 1 ]]; then
                  printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
                else
                  printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS'
                fi
                ;;
              extra-before-publication)
                if [[ "$asset_reads" -le 1 ]]; then
                  printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
                else
                  if [[ "$IDENTITY_MODE" == 'replace-before-cleanup' ]]; then
                    printf '202\n' > "$STATE/release-id"
                  fi
                  printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt' 'unexpected.bin'
                fi
                ;;
              enumeration-failure-before-publication)
                if [[ "$asset_reads" -le 1 ]]; then
                  printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
                else
                  printf '%s\n' 'SchneeGlass-0.1.0.zip'
                  exit 42
                fi
                ;;
              *)
                echo "unexpected asset fixture mode: $ASSET_MODE" >&2
                exit 104
                ;;
            esac
            ;;
          isImmutable)
            if [[ -f "$STATE/release-public" ]]; then printf 'true\n'; else printf 'false\n'; fi
            ;;
          *) echo "unexpected release view json field: $JSON" >&2; exit 97 ;;
        esac
        ;;
      create)
        touch "$STATE/release-created"
        printf '101\n' > "$STATE/release-id"
        ;;
      upload)
        [[ -f "$STATE/release-created" ]]
        ;;
      edit)
        [[ -f "$STATE/release-created" ]]
        FORCE_STABLE=false
        for arg in "$@"; do
          if [[ "$arg" == '--prerelease=false' ]]; then
            FORCE_STABLE=true
          fi
        done
        if [[ "$FORCE_STABLE" == true ]]; then
          rm -f "$STATE/release-prerelease"
        fi
        touch "$STATE/release-public"
        ;;
      delete)
        rm -f "$STATE/release-created" "$STATE/release-public" "$STATE/release-id"
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
export GH_FIXTURE_DRAFT_MODE='exact'
export GH_FIXTURE_PRERELEASE_MODE='stable'
export GH_FIXTURE_IDENTITY_MODE='stable'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
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

# Cleanup ownership must be tied to the exact Release object created by this run.
# If that Draft is replaced before a later asset failure, the replacement must not
# be deleted merely because it is also a mutable Draft with the same tag.
reset_case
export GH_FIXTURE_IDENTITY_MODE='replace-before-cleanup'
export GH_FIXTURE_ASSET_MODE='extra-before-publication'
OUTPUT_IDENTITY_CLEANUP="$FIXTURE/output-replacement-before-cleanup.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IDENTITY_CLEANUP" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: draft release asset set changed before publication' "$OUTPUT_IDENTITY_CLEANUP"
if grep -Fq 'gh release delete ' "$LOG"; then
  echo 'Replacement Draft was deleted by run-owned cleanup.' >&2
  FAILURES=$((FAILURES + 1))
fi
if [[ ! -f "$GH_FIXTURE_STATE/release-id" || "$(cat "$GH_FIXTURE_STATE/release-id")" != '202' ]]; then
  echo 'Replacement Draft identity did not survive failed run cleanup.' >&2
  FAILURES=$((FAILURES + 1))
fi
export GH_FIXTURE_IDENTITY_MODE='stable'
export GH_FIXTURE_ASSET_MODE='exact'

# Cleanup ownership must also remain valid after cleanup state probes. Replacing
# the same-tag Draft after the first identity proof but before delete must never
# authorize deletion based on stale identity.
reset_case
export GH_FIXTURE_IDENTITY_MODE='replace-after-cleanup-identity'
export GH_FIXTURE_ASSET_MODE='extra-before-publication'
OUTPUT_IDENTITY_CLEANUP_RACE="$FIXTURE/output-replacement-after-cleanup-identity.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IDENTITY_CLEANUP_RACE" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: draft release asset set changed before publication' "$OUTPUT_IDENTITY_CLEANUP_RACE"
if grep -Fq 'gh release delete ' "$LOG"; then
  echo 'Replacement Draft created after cleanup identity proof was deleted.' >&2
  FAILURES=$((FAILURES + 1))
fi
if [[ ! -f "$GH_FIXTURE_STATE/release-id" || "$(cat "$GH_FIXTURE_STATE/release-id")" != '202' ]]; then
  echo 'Replacement Draft identity did not survive the cleanup identity race.' >&2
  FAILURES=$((FAILURES + 1))
fi
export GH_FIXTURE_IDENTITY_MODE='stable'
export GH_FIXTURE_ASSET_MODE='exact'

# The same object identity must be certified immediately before publication.
# A same-tag replacement with otherwise valid target/assets must never be published.
reset_case
export GH_FIXTURE_IDENTITY_MODE='replace-before-publication'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_IDENTITY_PUBLICATION="$FIXTURE/output-replacement-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IDENTITY_PUBLICATION" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_IDENTITY_PUBLICATION"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after the run-owned Draft was replaced.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: draft release identity changed before publication' "$OUTPUT_IDENTITY_PUBLICATION"; then
    cat "$OUTPUT_IDENTITY_PUBLICATION"
    echo 'Replacement Draft did not fail with the expected identity error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Replacement Draft reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi
export GH_FIXTURE_IDENTITY_MODE='stable'

# Cleanup identity enumeration must itself fail closed without destructive action.
for identity_mode in cleanup-query-failure cleanup-malformed; do
  reset_case
  export GH_FIXTURE_IDENTITY_MODE="$identity_mode"
  export GH_FIXTURE_ASSET_MODE='extra-before-publication'
  OUTPUT_IDENTITY_CLEANUP_PROBE="$FIXTURE/output-$identity_mode.log"
  set +e
  bash Scripts/publish-notarized-release.sh >"$OUTPUT_IDENTITY_CLEANUP_PROBE" 2>&1
  STATUS=$?
  set -e
  [[ "$STATUS" -ne 0 ]]
  if grep -Fq 'gh release delete ' "$LOG"; then
    echo "Cleanup identity mode $identity_mode reached destructive release deletion." >&2
    FAILURES=$((FAILURES + 1))
  fi
done
export GH_FIXTURE_IDENTITY_MODE='stable'
export GH_FIXTURE_ASSET_MODE='exact'

# Final publication identity enumeration must preserve command failures and reject
# malformed IDs before Draft -> public.
reset_case
export GH_FIXTURE_IDENTITY_MODE='query-failure-before-publication'
OUTPUT_IDENTITY_QUERY_FAILURE="$FIXTURE/output-identity-query-failure-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IDENTITY_QUERY_FAILURE" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: unable to verify draft release identity before publication' "$OUTPUT_IDENTITY_QUERY_FAILURE"
! grep -Fq 'gh release edit ' "$LOG"

reset_case
export GH_FIXTURE_IDENTITY_MODE='malformed-before-publication'
OUTPUT_IDENTITY_MALFORMED="$FIXTURE/output-identity-malformed-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IDENTITY_MALFORMED" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: draft release identity is invalid before publication' "$OUTPUT_IDENTITY_MALFORMED"
! grep -Fq 'gh release edit ' "$LOG"
export GH_FIXTURE_IDENTITY_MODE='stable'

# Draft assets can change after the initial exact-set check. Missing assets must
# be rejected before Draft -> public, not only by post-publication verification.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='missing-before-publication'
OUTPUT_ASSET_MISSING="$FIXTURE/output-asset-missing-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_ASSET_MISSING" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_ASSET_MISSING"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after a Draft asset disappeared.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: draft release asset set changed before publication' "$OUTPUT_ASSET_MISSING"; then
    cat "$OUTPUT_ASSET_MISSING"
    echo 'Missing Draft asset did not fail with the expected pre-publication error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Missing Draft asset reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

# Unexpected assets added during the Draft window must fail at the same boundary.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='extra-before-publication'
OUTPUT_ASSET_EXTRA="$FIXTURE/output-asset-extra-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_ASSET_EXTRA" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_ASSET_EXTRA"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after an unexpected Draft asset appeared.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: draft release asset set changed before publication' "$OUTPUT_ASSET_EXTRA"; then
    cat "$OUTPUT_ASSET_EXTRA"
    echo 'Unexpected Draft asset did not fail with the expected pre-publication error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Unexpected Draft asset reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi
# Asset enumeration itself must also fail closed at the final Draft boundary.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='enumeration-failure-before-publication'
OUTPUT_ASSET_ENUMERATION_FAILURE="$FIXTURE/output-asset-enumeration-failure-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_ASSET_ENUMERATION_FAILURE" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: unable to enumerate draft release assets before publication' "$OUTPUT_ASSET_ENUMERATION_FAILURE"
! grep -Fq 'gh release edit ' "$LOG"
export GH_FIXTURE_ASSET_MODE='exact'

# The Draft can be published by another administrator after final asset
# enumeration but before this workflow performs Draft -> public. The workflow must
# detect that ownership/state transition before issuing its own release edit.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_DRAFT_MODE='publish-before-publication'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_DRAFT_PUBLISHED="$FIXTURE/output-draft-published-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_DRAFT_PUBLISHED" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_DRAFT_PUBLISHED"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after the Draft became public concurrently.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: release is no longer a Draft before publication' "$OUTPUT_DRAFT_PUBLISHED"; then
    cat "$OUTPUT_DRAFT_PUBLISHED"
    echo 'Concurrent Draft publication did not fail at the final pre-publication boundary.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Concurrent Draft publication reached this workflow Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi
export GH_FIXTURE_DRAFT_MODE='exact'

# The Draft target can also drift after its creation-time target check. That
# mismatch must be rejected before the immutable publication boundary.
reset_case
export GH_FIXTURE_TARGET_MODE='change-before-publication'
export GH_FIXTURE_DRAFT_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_TARGET_BEFORE="$FIXTURE/output-target-changed-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TARGET_BEFORE" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_TARGET_BEFORE"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after the Draft target changed.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: draft release target changed before publication' "$OUTPUT_TARGET_BEFORE"; then
    cat "$OUTPUT_TARGET_BEFORE"
    echo 'Draft target drift did not fail at the final pre-publication boundary.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Draft target drift reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi
export GH_FIXTURE_TARGET_MODE='exact'

# Final Draft-state enumeration itself must fail closed, including partial output.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_DRAFT_MODE='query-failure-before-publication'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_DRAFT_QUERY_FAILURE="$FIXTURE/output-draft-query-failure-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_DRAFT_QUERY_FAILURE" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: unable to verify draft release state before publication' "$OUTPUT_DRAFT_QUERY_FAILURE"
! grep -Fq 'gh release edit ' "$LOG"

# A malformed Draft state is not positive proof of ownership/state.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_DRAFT_MODE='invalid-before-publication'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_DRAFT_INVALID="$FIXTURE/output-draft-invalid-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_DRAFT_INVALID" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: release is no longer a Draft before publication' "$OUTPUT_DRAFT_INVALID"
! grep -Fq 'gh release edit ' "$LOG"
export GH_FIXTURE_DRAFT_MODE='exact'

# Final Draft-target enumeration must preserve command failure even with plausible output.
reset_case
export GH_FIXTURE_TARGET_MODE='query-failure-before-publication'
export GH_FIXTURE_DRAFT_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_TARGET_QUERY_FAILURE="$FIXTURE/output-target-query-failure-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TARGET_QUERY_FAILURE" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: unable to verify draft release target before publication' "$OUTPUT_TARGET_QUERY_FAILURE"
! grep -Fq 'gh release edit ' "$LOG"

# Non-SHA target values must also fail before publication.
reset_case
export GH_FIXTURE_TARGET_MODE='malformed-before-publication'
export GH_FIXTURE_DRAFT_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_TARGET_MALFORMED="$FIXTURE/output-target-malformed-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TARGET_MALFORMED" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: draft release target returned an invalid commit SHA before publication' "$OUTPUT_TARGET_MALFORMED"
! grep -Fq 'gh release edit ' "$LOG"
export GH_FIXTURE_TARGET_MODE='exact'

# A stable Draft can be changed into a prerelease during the final Draft window.
# Stable publication must re-read that classification before publishing.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_DRAFT_MODE='exact'
export GH_FIXTURE_PRERELEASE_MODE='change-before-publication'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
OUTPUT_PRERELEASE_CHANGED="$FIXTURE/output-prerelease-changed-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_PRERELEASE_CHANGED" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_PRERELEASE_CHANGED"
  cat "$LOG"
  echo 'Stable publication unexpectedly succeeded after the Draft became a prerelease.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: release became a prerelease before stable publication' "$OUTPUT_PRERELEASE_CHANGED"; then
    cat "$OUTPUT_PRERELEASE_CHANGED"
    echo 'Prerelease drift did not fail at the final stable-publication boundary.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Prerelease drift reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

# Even after a successful final classification read, another administrator can
# flip the mutable Draft before the publish mutation. The mutation itself must
# explicitly force stable classification so this race cannot persist.
reset_case
export GH_FIXTURE_PRERELEASE_MODE='change-after-final-check'
OUTPUT_PRERELEASE_AFTER_CHECK="$FIXTURE/output-prerelease-after-final-check.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_PRERELEASE_AFTER_CHECK" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -ne 0 ]]; then
  cat "$OUTPUT_PRERELEASE_AFTER_CHECK"
  cat "$LOG"
  echo 'Stable publication failed while exercising post-check prerelease race.' >&2
  FAILURES=$((FAILURES + 1))
else
  if [[ -f "$GH_FIXTURE_STATE/release-prerelease" ]]; then
    echo 'Publication mutation did not atomically clear prerelease classification.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if ! grep -Fq -- '--prerelease=false' "$LOG"; then
    echo 'Publication mutation did not explicitly force prerelease=false.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi
export GH_FIXTURE_PRERELEASE_MODE='stable'

# The final prerelease probe itself must preserve command failure.
reset_case
export GH_FIXTURE_PRERELEASE_MODE='query-failure-before-publication'
OUTPUT_PRERELEASE_QUERY_FAILURE="$FIXTURE/output-prerelease-query-failure-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_PRERELEASE_QUERY_FAILURE" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: unable to verify prerelease state before publication' "$OUTPUT_PRERELEASE_QUERY_FAILURE"
! grep -Fq 'gh release edit ' "$LOG"

# Malformed prerelease state is not positive proof of a stable release.
reset_case
export GH_FIXTURE_PRERELEASE_MODE='malformed-before-publication'
OUTPUT_PRERELEASE_MALFORMED="$FIXTURE/output-prerelease-malformed-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_PRERELEASE_MALFORMED" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: prerelease state is malformed before publication' "$OUTPUT_PRERELEASE_MALFORMED"
! grep -Fq 'gh release edit ' "$LOG"
export GH_FIXTURE_PRERELEASE_MODE='stable'

# Release immutability can drift after earlier governance checks. A disabled
# setting must fail before Draft -> public instead of relying on post-publication cleanup.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_DRAFT_MODE='exact'
export GH_FIXTURE_TAG_MODE='exact'
export GH_FIXTURE_ASSET_MODE='exact'
export GH_FIXTURE_IMMUTABILITY_MODE='disabled'
OUTPUT_IMMUTABILITY_DISABLED="$FIXTURE/output-immutability-disabled-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IMMUTABILITY_DISABLED" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_IMMUTABILITY_DISABLED"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded with repository immutability disabled.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: release immutability is not enabled before publication' "$OUTPUT_IMMUTABILITY_DISABLED"; then
    cat "$OUTPUT_IMMUTABILITY_DISABLED"
    echo 'Disabled release immutability did not fail at the final publication boundary.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Disabled release immutability reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

# The final immutability probe itself must fail closed on API error, even when it
# emits a plausible enabled response first.
reset_case
export GH_FIXTURE_IMMUTABILITY_MODE='query-failure'
OUTPUT_IMMUTABILITY_QUERY_FAILURE="$FIXTURE/output-immutability-query-failure-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IMMUTABILITY_QUERY_FAILURE" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: unable to verify release immutability before publication' "$OUTPUT_IMMUTABILITY_QUERY_FAILURE"
! grep -Fq 'gh release edit ' "$LOG"

# Malformed API responses are not positive proof that immutability is enabled.
reset_case
export GH_FIXTURE_IMMUTABILITY_MODE='malformed'
OUTPUT_IMMUTABILITY_MALFORMED="$FIXTURE/output-immutability-malformed-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_IMMUTABILITY_MALFORMED" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: release immutability response is malformed before publication' "$OUTPUT_IMMUTABILITY_MALFORMED"
! grep -Fq 'gh release edit ' "$LOG"
export GH_FIXTURE_IMMUTABILITY_MODE='enabled'

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

# Draft tag provenance must be re-read before publication. A retargeted tag must
# fail before the Draft-to-public mutation, not only after publication.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='retarget-before-publication'
export GH_FIXTURE_GOVERNANCE_MODE='valid'
OUTPUT_TAG_RETARGETED="$FIXTURE/output-tag-retargeted-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TAG_RETARGETED" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_TAG_RETARGETED"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded with a retargeted Draft tag.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: release tag no longer resolves to candidate source commit before publication' "$OUTPUT_TAG_RETARGETED"; then
    cat "$OUTPUT_TAG_RETARGETED"
    echo 'Retargeted Draft tag did not fail with the expected pre-publication error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Retargeted Draft tag reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi

# The same final boundary must fail closed if the Draft-associated tag disappears.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='missing-before-publication'
export GH_FIXTURE_GOVERNANCE_MODE='valid'
OUTPUT_TAG_MISSING="$FIXTURE/output-tag-missing-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TAG_MISSING" 2>&1
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT_TAG_MISSING"
  cat "$LOG"
  echo 'Release publication unexpectedly succeeded after the Draft tag disappeared.' >&2
  FAILURES=$((FAILURES + 1))
else
  if ! grep -Fq 'Release promotion failed: unable to verify release tag before publication' "$OUTPUT_TAG_MISSING"; then
    cat "$OUTPUT_TAG_MISSING"
    echo 'Missing Draft tag did not fail with the expected pre-publication error.' >&2
    FAILURES=$((FAILURES + 1))
  fi
  if grep -Fq 'gh release edit ' "$LOG"; then
    echo 'Missing Draft tag reached the Draft-to-public mutation.' >&2
    FAILURES=$((FAILURES + 1))
  fi
fi
export GH_FIXTURE_TAG_MODE='exact'

# Multiple remote refs are ambiguous and must fail before publication.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='ambiguous-before-publication'
export GH_FIXTURE_GOVERNANCE_MODE='valid'
OUTPUT_TAG_AMBIGUOUS="$FIXTURE/output-tag-ambiguous-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TAG_AMBIGUOUS" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: release tag returned an invalid remote ref set before publication' "$OUTPUT_TAG_AMBIGUOUS"
! grep -Fq 'gh release edit ' "$LOG"

# Malformed tag provenance must also fail before publication.
reset_case
export GH_FIXTURE_TARGET_MODE='exact'
export GH_FIXTURE_TAG_MODE='malformed-before-publication'
export GH_FIXTURE_GOVERNANCE_MODE='valid'
OUTPUT_TAG_MALFORMED="$FIXTURE/output-tag-malformed-before-publication.log"
set +e
bash Scripts/publish-notarized-release.sh >"$OUTPUT_TAG_MALFORMED" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'Release promotion failed: release tag returned an invalid remote ref before publication' "$OUTPUT_TAG_MALFORMED"
! grep -Fq 'gh release edit ' "$LOG"
export GH_FIXTURE_TAG_MODE='exact'

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
export GH_FIXTURE_TAG_MODE='mismatch-after-publication'
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
