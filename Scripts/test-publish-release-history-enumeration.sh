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
mkdir -p "$GH_FIXTURE_STATE"

cat > "$FIXTURE/bin/git" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
printf 'git ' >> "${GH_FIXTURE_LOG:?}"
printf '%q ' "$@" >> "$GH_FIXTURE_LOG"
printf '\n' >> "$GH_FIXTURE_LOG"

case "${1:-}" in
  rev-parse)
    [[ "${2:-}" == '--show-toplevel' ]]
    printf '%s\n' "${GH_FIXTURE_ROOT:?}"
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
        echo 'fixture: release history API unavailable' >&2
        exit 42
        ;;
      *)
        echo "unexpected gh api endpoint: $ENDPOINT" >&2
        exit 93
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
          exit 94
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
              exit 95
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
            printf '%s\n' 'SchneeGlass-0.1.0.zip' 'SHA256SUMS' 'RELEASE_EVIDENCE.txt'
            ;;
          isImmutable) printf 'true\n' ;;
          *) echo "unexpected release view json field: $JSON" >&2; exit 96 ;;
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
        echo 'historical release download must not be reached when enumeration fails' >&2
        exit 97
        ;;
      delete)
        rm -f "$STATE/release-created" "$STATE/release-public"
        ;;
      *)
        echo "unexpected gh release subcommand: $SUBCOMMAND" >&2
        exit 98
        ;;
    esac
    ;;

  *)
    echo "unexpected gh command: $COMMAND $*" >&2
    exit 99
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

OUTPUT="$FIXTURE/output.log"
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

rm -rf "$FIXTURE"
echo 'Release history enumeration failure fixture passed'
