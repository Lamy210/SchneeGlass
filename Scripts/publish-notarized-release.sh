#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

fail() {
  echo "Release promotion failed: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "required promotion environment value is missing: $name"
}

for name in \
  RELEASE_VERSION \
  CANDIDATE_RUN_ID \
  GITHUB_REPOSITORY \
  GITHUB_REF \
  GH_TOKEN \
  CONFIRM_MANUAL_QA \
  CONFIRM_IMMUTABLE_RELEASES \
  CONFIRM_RELEASE_GOVERNANCE \
  CONFIRM_PUBLISH; do
  require_env "$name"
done

[[ "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "RELEASE_VERSION must be X.Y.Z"
[[ "$CANDIDATE_RUN_ID" =~ ^[0-9]+$ ]] \
  || fail "CANDIDATE_RUN_ID must be numeric"
[[ "$GITHUB_REF" == 'refs/heads/main' ]] \
  || fail "production release publication is restricted to main"
[[ "$CONFIRM_MANUAL_QA" == 'true' ]] \
  || fail "manual QA confirmation is required"
[[ "$CONFIRM_IMMUTABLE_RELEASES" == 'true' ]] \
  || fail "immutable releases confirmation is required"
[[ "$CONFIRM_RELEASE_GOVERNANCE" == 'true' ]] \
  || fail "release governance confirmation is required"
[[ "$CONFIRM_PUBLISH" == 'true' ]] \
  || fail "explicit publish confirmation is required"

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v shasum >/dev/null 2>&1 || fail "shasum is required"

TAG="v${RELEASE_VERSION}"
ARTIFACT_NAME="SchneeGlass-${RELEASE_VERSION}-signed-notarized-candidate"
ARCHIVE_NAME="SchneeGlass-${RELEASE_VERSION}.zip"
RUNNER_TEMP="${RUNNER_TEMP:-/tmp}"
CANDIDATE_DIR="$RUNNER_TEMP/SchneeGlassReleasePromotion"
HISTORY_DIR="$CANDIDATE_DIR/published-build-history"
CREATED_RELEASE=false
PUBLICATION_COMMAND_SUCCEEDED=false

release_asset_set_is_exact() {
  local asset_names="$1"
  local asset_name=''
  local total=0
  local archive_count=0
  local checksums_count=0
  local evidence_count=0

  while IFS= read -r asset_name; do
    [[ -n "$asset_name" ]] || continue
    total=$((total + 1))
    case "$asset_name" in
      "$ARCHIVE_NAME") archive_count=$((archive_count + 1)) ;;
      SHA256SUMS) checksums_count=$((checksums_count + 1)) ;;
      RELEASE_EVIDENCE.txt) evidence_count=$((evidence_count + 1)) ;;
      *) return 1 ;;
    esac
  done <<< "$asset_names"

  [[ "$total" -eq 3 \
    && "$archive_count" -eq 1 \
    && "$checksums_count" -eq 1 \
    && "$evidence_count" -eq 1 ]]
}

cleanup() {
  set +e
  rm -rf "$CANDIDATE_DIR"

  if [[ "$CREATED_RELEASE" == 'true' && "$PUBLICATION_COMMAND_SUCCEEDED" != 'true' ]]; then
    CLEANUP_IS_DRAFT=''
    CLEANUP_IS_IMMUTABLE=''

    if ! CLEANUP_IS_DRAFT="$(gh release view "$TAG" \
      --repo "$GITHUB_REPOSITORY" \
      --json isDraft \
      --jq '.isDraft' 2>/dev/null)"; then
      echo "Release cleanup skipped for $TAG: draft state is unavailable; manual reconciliation required." >&2
      return
    fi

    if ! CLEANUP_IS_IMMUTABLE="$(gh release view "$TAG" \
      --repo "$GITHUB_REPOSITORY" \
      --json isImmutable \
      --jq '.isImmutable' 2>/dev/null)"; then
      echo "Release cleanup skipped for $TAG: immutability state is unavailable; manual reconciliation required." >&2
      return
    fi

    if [[ "$CLEANUP_IS_DRAFT" == 'true' && "$CLEANUP_IS_IMMUTABLE" == 'false' ]]; then
      if ! gh release delete "$TAG" \
        --repo "$GITHUB_REPOSITORY" \
        --cleanup-tag \
        --yes >/dev/null 2>&1; then
        echo "Release cleanup failed for $TAG: unable to delete run-owned mutable Draft/tag; manual reconciliation required." >&2
      fi
      return
    fi

    if [[ "$CLEANUP_IS_DRAFT" != 'false' && "$CLEANUP_IS_DRAFT" != 'true' ]] \
      || [[ "$CLEANUP_IS_IMMUTABLE" != 'false' && "$CLEANUP_IS_IMMUTABLE" != 'true' ]]; then
      echo "Release cleanup skipped for $TAG: release state is invalid; manual reconciliation required." >&2
      return
    fi

    echo "Release cleanup skipped for $TAG: release is no longer a mutable Draft; manual reconciliation required." >&2
  fi
}
trap cleanup EXIT

rm -rf "$CANDIDATE_DIR"
mkdir -p "$CANDIDATE_DIR" "$HISTORY_DIR"

RUN_API="repos/$GITHUB_REPOSITORY/actions/runs/$CANDIDATE_RUN_ID"
RUN_NAME="$(gh api "$RUN_API" --jq '.name')"
RUN_PATH="$(gh api "$RUN_API" --jq '.path')"
RUN_EVENT="$(gh api "$RUN_API" --jq '.event')"
RUN_STATUS="$(gh api "$RUN_API" --jq '.status')"
RUN_CONCLUSION="$(gh api "$RUN_API" --jq '.conclusion')"
RUN_BRANCH="$(gh api "$RUN_API" --jq '.head_branch')"
RUN_HEAD_SHA="$(gh api "$RUN_API" --jq '.head_sha')"

bash Scripts/verify-production-candidate-run.sh \
  "$RUN_NAME" \
  "$RUN_PATH" \
  "$RUN_EVENT" \
  "$RUN_STATUS" \
  "$RUN_CONCLUSION" \
  "$RUN_BRANCH" \
  "$RUN_HEAD_SHA"

gh run download "$CANDIDATE_RUN_ID" \
  --repo "$GITHUB_REPOSITORY" \
  --name "$ARTIFACT_NAME" \
  --dir "$CANDIDATE_DIR"

ARCHIVE="$CANDIDATE_DIR/$ARCHIVE_NAME"
CHECKSUMS="$CANDIDATE_DIR/SHA256SUMS"
EVIDENCE="$CANDIDATE_DIR/RELEASE_EVIDENCE.txt"

test -f "$ARCHIVE" || fail "candidate archive is missing"
test -f "$CHECKSUMS" || fail "SHA256SUMS is missing"
test -f "$EVIDENCE" || fail "RELEASE_EVIDENCE.txt is missing"

bash Scripts/verify-release-evidence.sh "$EVIDENCE" "$RELEASE_VERSION" "$RUN_HEAD_SHA"

bash Scripts/verify-release-checksum-manifest.sh "$CANDIDATE_DIR" "$ARCHIVE_NAME"

# Every public (non-draft) release is distribution history, including prereleases.
# Download its release evidence and require the new build number to exceed the
# maximum previously distributed build. Missing/malformed history fails closed.
PUBLISHED_TAGS="$CANDIDATE_DIR/published-release-tags.txt"
if ! gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
  --jq '.[] | select(.draft == false) | .tag_name' \
  > "$PUBLISHED_TAGS"; then
  fail "failed to enumerate public release history"
fi

HISTORY_INDEX=0
while IFS= read -r PUBLISHED_TAG; do
  [[ -n "$PUBLISHED_TAG" ]] || continue
  HISTORY_INDEX=$((HISTORY_INDEX + 1))
  RELEASE_HISTORY_DIR="$HISTORY_DIR/$HISTORY_INDEX"
  mkdir -p "$RELEASE_HISTORY_DIR"

  gh release download "$PUBLISHED_TAG" \
    --repo "$GITHUB_REPOSITORY" \
    --pattern 'RELEASE_EVIDENCE.txt' \
    --dir "$RELEASE_HISTORY_DIR" \
    || fail "public release $PUBLISHED_TAG is missing readable RELEASE_EVIDENCE.txt"

  test -f "$RELEASE_HISTORY_DIR/RELEASE_EVIDENCE.txt" \
    || fail "public release $PUBLISHED_TAG did not yield RELEASE_EVIDENCE.txt"
done < "$PUBLISHED_TAGS"

bash Scripts/verify-release-build-history.sh "$EVIDENCE" "$HISTORY_DIR"

git fetch origin main --tags --force
git cat-file -e "$RUN_HEAD_SHA^{commit}" \
  || fail "candidate source commit is not available in repository history"
CURRENT_MAIN_SHA="$(git rev-parse origin/main)" \
  || fail "unable to resolve current main commit"
[[ "$CURRENT_MAIN_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "current main returned an invalid commit SHA: $CURRENT_MAIN_SHA"
[[ "$RUN_HEAD_SHA" == "$CURRENT_MAIN_SHA" ]] \
  || fail "candidate source commit does not match current main: candidate=$RUN_HEAD_SHA current=$CURRENT_MAIN_SHA"

set +e
git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1
TAG_PROBE_STATUS=$?
set -e

case "$TAG_PROBE_STATUS" in
  0)
    fail "release tag already exists: $TAG"
    ;;
  2)
    ;;
  *)
    fail "unable to determine whether release tag already exists: $TAG"
    ;;
esac

EXISTING_RELEASE_TAGS="$CANDIDATE_DIR/existing-release-tags.txt"
if ! gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
  --jq '.[] | .tag_name' \
  > "$EXISTING_RELEASE_TAGS"; then
  fail "unable to determine whether GitHub Release already exists: $TAG"
fi
set +e
grep -Fxq "$TAG" "$EXISTING_RELEASE_TAGS"
EXISTING_RELEASE_MATCH_STATUS=$?
set -e

case "$EXISTING_RELEASE_MATCH_STATUS" in
  0)
    fail "GitHub Release already exists: $TAG"
    ;;
  1)
    ;;
  *)
    fail "unable to determine whether GitHub Release already exists: $TAG"
    ;;
esac

# Create the draft without assets first. Only a successful create establishes ownership
# for cleanup, avoiding deletion of a concurrently-created release on create failure.
gh release create "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --target "$RUN_HEAD_SHA" \
  --title "SchneeGlass ${RELEASE_VERSION}" \
  --generate-notes \
  --draft
CREATED_RELEASE=true

IS_DRAFT="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json isDraft \
  --jq '.isDraft')"
[[ "$IS_DRAFT" == 'true' ]] || fail "release was not created as draft"

RELEASE_TARGET="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json targetCommitish \
  --jq '.targetCommitish')"
[[ "$RELEASE_TARGET" == "$RUN_HEAD_SHA" ]] \
  || fail "draft release target mismatch: expected $RUN_HEAD_SHA, got $RELEASE_TARGET"

gh release upload "$TAG" \
  "$ARCHIVE" \
  "$CHECKSUMS" \
  "$EVIDENCE" \
  --repo "$GITHUB_REPOSITORY"

if ! ASSET_NAMES="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json assets \
  --jq '.assets[].name')"; then
  fail "unable to enumerate draft release assets"
fi
release_asset_set_is_exact "$ASSET_NAMES" \
  || fail "draft release asset set does not exactly match expected public assets"

# Draft preparation can take long enough for main to advance after the initial provenance
# check. Re-fetch immediately before publication so an older candidate can never become
# the immutable public Release merely because it was current when Draft creation started.
git fetch origin main --force
FINAL_MAIN_SHA="$(git rev-parse origin/main)" \
  || fail "unable to resolve current main commit before publication"
[[ "$FINAL_MAIN_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "current main returned an invalid commit SHA before publication: $FINAL_MAIN_SHA"
[[ "$RUN_HEAD_SHA" == "$FINAL_MAIN_SHA" ]] \
  || fail "candidate source commit does not match current main before publication: candidate=$RUN_HEAD_SHA current=$FINAL_MAIN_SHA"

if ! bash Scripts/verify-current-release-governance.sh "$GITHUB_REPOSITORY"; then
  fail "current release governance is no longer valid before publication"
fi

PREPUBLICATION_TAG_LINE=''
PREPUBLICATION_TAG_STATUS=0
set +e
PREPUBLICATION_TAG_LINE="$(git ls-remote --exit-code --tags origin "refs/tags/$TAG")"
PREPUBLICATION_TAG_STATUS=$?
set -e

[[ "$PREPUBLICATION_TAG_STATUS" -eq 0 ]] \
  || fail "unable to verify release tag before publication"

PREPUBLICATION_TAG_LINE_COUNT=''
PREPUBLICATION_TAG_LINE_COUNT_STATUS=0
set +e
PREPUBLICATION_TAG_LINE_COUNT="$(printf '%s\n' "$PREPUBLICATION_TAG_LINE" | awk 'END { print NR }')"
PREPUBLICATION_TAG_LINE_COUNT_STATUS=$?
set -e

[[ "$PREPUBLICATION_TAG_LINE_COUNT_STATUS" -eq 0 ]] \
  || fail "unable to enumerate release tag refs before publication"
[[ "$PREPUBLICATION_TAG_LINE_COUNT" =~ ^[0-9]+$ && "$PREPUBLICATION_TAG_LINE_COUNT" -eq 1 ]] \
  || fail "release tag returned an invalid remote ref set before publication"

PREPUBLICATION_TAG_SHA=''
PREPUBLICATION_TAG_REF=''
PREPUBLICATION_TAG_EXTRA=''
read -r PREPUBLICATION_TAG_SHA PREPUBLICATION_TAG_REF PREPUBLICATION_TAG_EXTRA <<< "$PREPUBLICATION_TAG_LINE"
[[ -z "$PREPUBLICATION_TAG_EXTRA" ]] \
  || fail "release tag returned an invalid remote ref set before publication"
[[ "$PREPUBLICATION_TAG_SHA" =~ ^[0-9a-f]{40}$ && "$PREPUBLICATION_TAG_REF" == "refs/tags/$TAG" ]] \
  || fail "release tag returned an invalid remote ref before publication"
[[ "$PREPUBLICATION_TAG_SHA" == "$RUN_HEAD_SHA" ]] \
  || fail "release tag no longer resolves to candidate source commit before publication"

if ! PREPUBLICATION_ASSET_NAMES="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json assets \
  --jq '.assets[].name')"; then
  fail "unable to enumerate draft release assets before publication"
fi
release_asset_set_is_exact "$PREPUBLICATION_ASSET_NAMES" \
  || fail "draft release asset set changed before publication"

if ! PREPUBLICATION_IS_DRAFT="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json isDraft \
  --jq '.isDraft')"; then
  fail "unable to verify draft release state before publication"
fi
[[ "$PREPUBLICATION_IS_DRAFT" == 'true' ]] \
  || fail "release is no longer a Draft before publication"

if ! PREPUBLICATION_RELEASE_TARGET="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json targetCommitish \
  --jq '.targetCommitish')"; then
  fail "unable to verify draft release target before publication"
fi
[[ "$PREPUBLICATION_RELEASE_TARGET" =~ ^[0-9a-f]{40}$ ]] \
  || fail "draft release target returned an invalid commit SHA before publication"
[[ "$PREPUBLICATION_RELEASE_TARGET" == "$RUN_HEAD_SHA" ]] \
  || fail "draft release target changed before publication"

PREPUBLICATION_IMMUTABILITY_JSON="$CANDIDATE_DIR/prepublication-immutable-releases.json"
if ! gh api \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  "repos/$GITHUB_REPOSITORY/immutable-releases" \
  > "$PREPUBLICATION_IMMUTABILITY_JSON"; then
  fail "unable to verify release immutability before publication"
fi
jq -e 'type == "object" and has("enabled") and (.enabled | type == "boolean")' \
  "$PREPUBLICATION_IMMUTABILITY_JSON" >/dev/null \
  || fail "release immutability response is malformed before publication"
jq -e '.enabled == true' "$PREPUBLICATION_IMMUTABILITY_JSON" >/dev/null \
  || fail "release immutability is not enabled before publication"

gh release edit "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --draft=false \
  --latest
PUBLICATION_COMMAND_SUCCEEDED=true

if ! IS_DRAFT="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json isDraft \
  --jq '.isDraft')"; then
  fail "unable to verify published release draft state; publication state is ambiguous and requires manual reconciliation"
fi

if [[ "$IS_DRAFT" != 'false' ]]; then
  if [[ "$IS_DRAFT" == 'true' ]]; then
    PUBLICATION_COMMAND_SUCCEEDED=false
    fail "release did not become public"
  fi
  fail "published release returned invalid draft state; publication state is ambiguous and requires manual reconciliation"
fi

if ! IS_IMMUTABLE="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json isImmutable \
  --jq '.isImmutable')"; then
  fail "unable to verify published release immutability; publication state is ambiguous and requires manual reconciliation"
fi

if [[ "$IS_IMMUTABLE" == 'false' ]]; then
  gh release delete "$TAG" \
    --repo "$GITHUB_REPOSITORY" \
    --cleanup-tag \
    --yes \
    || fail "published release is mutable and automatic cleanup failed"

  MUTABLE_CLEANUP_RELEASE_TAGS="$CANDIDATE_DIR/mutable-cleanup-release-tags.txt"
  if ! gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
    --jq '.[] | .tag_name' \
    > "$MUTABLE_CLEANUP_RELEASE_TAGS"; then
    fail "unable to verify mutable release cleanup; publication state is ambiguous and requires manual reconciliation"
  fi
  set +e
  grep -Fxq "$TAG" "$MUTABLE_CLEANUP_RELEASE_TAGS"
  MUTABLE_RELEASE_MATCH_STATUS=$?
  set -e

  case "$MUTABLE_RELEASE_MATCH_STATUS" in
    0)
      fail "mutable release still exists after cleanup"
      ;;
    1)
      ;;
    *)
      fail "unable to verify mutable release cleanup; publication state is ambiguous and requires manual reconciliation"
      ;;
  esac

  set +e
  git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1
  MUTABLE_TAG_PROBE_STATUS=$?
  set -e

  case "$MUTABLE_TAG_PROBE_STATUS" in
    0)
      fail "mutable release tag still exists after cleanup"
      ;;
    2)
      ;;
    *)
      fail "unable to verify mutable release tag cleanup; publication state is ambiguous and requires manual reconciliation"
      ;;
  esac

  CREATED_RELEASE=false
  fail "published release was not immutable and was removed; enable repository release immutability before retrying"
fi

[[ "$IS_IMMUTABLE" == 'true' ]] \
  || fail "published release returned invalid immutability state; publication state is ambiguous and requires manual reconciliation"

if ! PUBLISHED_ASSET_NAMES="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json assets \
  --jq '.assets[].name')"; then
  fail "unable to verify published release assets; publication state is ambiguous and requires manual reconciliation"
fi
release_asset_set_is_exact "$PUBLISHED_ASSET_NAMES" \
  || fail "published release asset set does not exactly match expected public assets; publication state is ambiguous and requires manual reconciliation"

if ! PUBLISHED_RELEASE_TARGET="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json targetCommitish \
  --jq '.targetCommitish')"; then
  fail "unable to verify published release target; publication state is ambiguous and requires manual reconciliation"
fi
[[ "$PUBLISHED_RELEASE_TARGET" == "$RUN_HEAD_SHA" ]] \
  || fail "published release target does not match candidate source commit; publication state is ambiguous and requires manual reconciliation"

if ! PUBLISHED_TAG_LINE="$(git ls-remote --exit-code --tags origin "refs/tags/$TAG")"; then
  fail "unable to verify published release tag; publication state is ambiguous and requires manual reconciliation"
fi
[[ "$PUBLISHED_TAG_LINE" != *$'\n'* ]] \
  || fail "published release tag returned an invalid remote ref set; publication state is ambiguous and requires manual reconciliation"
PUBLISHED_TAG_SHA=''
PUBLISHED_TAG_REF=''
IFS=$'\t' read -r PUBLISHED_TAG_SHA PUBLISHED_TAG_REF <<< "$PUBLISHED_TAG_LINE"
[[ "$PUBLISHED_TAG_SHA" =~ ^[0-9a-f]{40}$ && "$PUBLISHED_TAG_REF" == "refs/tags/$TAG" ]] \
  || fail "published release tag returned an invalid remote ref; publication state is ambiguous and requires manual reconciliation"
[[ "$PUBLISHED_TAG_SHA" == "$RUN_HEAD_SHA" ]] \
  || fail "published release tag does not resolve to candidate source commit; publication state is ambiguous and requires manual reconciliation"

CREATED_RELEASE=false
trap - EXIT
rm -rf "$CANDIDATE_DIR"

echo "Published immutable release $TAG from candidate run $CANDIDATE_RUN_ID ($RUN_HEAD_SHA)."
