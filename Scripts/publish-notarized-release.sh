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

command -v curl >/dev/null 2>&1 || fail "curl is required"
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
CREATED_RELEASE_ID=''
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

sha256_digest_for_file() {
  local path="$1"
  local digest=''

  if ! digest="$(shasum -a 256 "$path" | awk '{print $1}')"; then
    fail "unable to compute SHA-256 digest for $path"
  fi
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] \
    || fail "SHA-256 digest computation returned an invalid value for $path"

  printf 'sha256:%s\n' "$digest"
}

release_asset_digests_match_expected() {
  local release_json="$1"

  jq -e \
    --arg archive_name "$ARCHIVE_NAME" \
    --arg archive_digest "$ARCHIVE_DIGEST" \
    --arg checksums_digest "$CHECKSUMS_DIGEST" \
    --arg evidence_digest "$EVIDENCE_DIGEST" \
    '
      (.assets | type == "array") and
      (.assets | length == 3) and
      ((.assets | map(.name) | sort) == ([$archive_name, "SHA256SUMS", "RELEASE_EVIDENCE.txt"] | sort)) and
      (.assets | all(.[];
        (.digest | type == "string") and
        (.digest | test("^sha256:[0-9a-f]{64}$"))
      )) and
      (.assets | any(.[]; .name == $archive_name and .digest == $archive_digest)) and
      (.assets | any(.[]; .name == "SHA256SUMS" and .digest == $checksums_digest)) and
      (.assets | any(.[]; .name == "RELEASE_EVIDENCE.txt" and .digest == $evidence_digest))
    ' \
    "$release_json" >/dev/null
}

upload_release_asset_by_id() {
  local asset_path="$1"
  local asset_name="$2"
  local content_type="$3"
  local upload_url="https://uploads.github.com/repos/$GITHUB_REPOSITORY/releases/$CREATED_RELEASE_ID/assets?name=$asset_name"

  if ! curl \
    --fail-with-body \
    --silent \
    --show-error \
    --location \
    --request POST \
    --header 'Accept: application/vnd.github+json' \
    --header "Authorization: Bearer $GH_TOKEN" \
    --header 'X-GitHub-Api-Version: 2026-03-10' \
    --header "Content-Type: $content_type" \
    --data-binary "@$asset_path" \
    "$upload_url" \
    >/dev/null; then
    fail "unable to upload release asset $asset_name to run-owned Release ID $CREATED_RELEASE_ID; remote state may be ambiguous and requires manual reconciliation"
  fi
}

cleanup_guidance() {
  local reason="$1"
  local release_id="${CREATED_RELEASE_ID:-unavailable}"

  echo "Release cleanup is non-destructive for $TAG (release ID $release_id): $reason; no remote Release/tag cleanup was attempted; manual reconciliation required." >&2
}

cleanup() {
  set +e
  rm -rf "$CANDIDATE_DIR"

  if [[ "$CREATED_RELEASE" == 'true' && "$PUBLICATION_COMMAND_SUCCEEDED" != 'true' ]]; then
    if [[ -z "$CREATED_RELEASE_ID" ]]; then
      cleanup_guidance "Draft creation succeeded but its Release identity was not captured"
      return
    fi

    CLEANUP_RELEASE_ID=''
    CLEANUP_IS_DRAFT=''
    CLEANUP_IS_IMMUTABLE=''

    if ! CLEANUP_RELEASE_ID="$(gh release view "$TAG" \
      --repo "$GITHUB_REPOSITORY" \
      --json databaseId \
      --jq '.databaseId' 2>/dev/null)"; then
      cleanup_guidance "release identity is unavailable"
      return
    fi
    if [[ ! "$CLEANUP_RELEASE_ID" =~ ^[1-9][0-9]*$ ]]; then
      cleanup_guidance "release identity is invalid"
      return
    fi
    if [[ "$CLEANUP_RELEASE_ID" != "$CREATED_RELEASE_ID" ]]; then
      cleanup_guidance "release identity changed"
      return
    fi

    if ! CLEANUP_IS_DRAFT="$(gh release view "$TAG" \
      --repo "$GITHUB_REPOSITORY" \
      --json isDraft \
      --jq '.isDraft' 2>/dev/null)"; then
      cleanup_guidance "draft state is unavailable"
      return
    fi

    if ! CLEANUP_IS_IMMUTABLE="$(gh release view "$TAG" \
      --repo "$GITHUB_REPOSITORY" \
      --json isImmutable \
      --jq '.isImmutable' 2>/dev/null)"; then
      cleanup_guidance "immutability state is unavailable"
      return
    fi

    if [[ "$CLEANUP_IS_DRAFT" == 'true' && "$CLEANUP_IS_IMMUTABLE" == 'false' ]]; then
      FINAL_CLEANUP_RELEASE_ID=''
      if ! FINAL_CLEANUP_RELEASE_ID="$(gh release view "$TAG" \
        --repo "$GITHUB_REPOSITORY" \
        --json databaseId \
        --jq '.databaseId' 2>/dev/null)"; then
        cleanup_guidance "final release identity is unavailable"
        return
      fi
      if [[ ! "$FINAL_CLEANUP_RELEASE_ID" =~ ^[1-9][0-9]*$ ]]; then
        cleanup_guidance "final release identity is invalid"
        return
      fi
      if [[ "$FINAL_CLEANUP_RELEASE_ID" != "$CREATED_RELEASE_ID" ]]; then
        cleanup_guidance "final release identity changed"
        return
      fi

      cleanup_guidance "remote state may change after validation"
      return
    fi

    if [[ "$CLEANUP_IS_DRAFT" != 'false' && "$CLEANUP_IS_DRAFT" != 'true' ]] \
      || [[ "$CLEANUP_IS_IMMUTABLE" != 'false' && "$CLEANUP_IS_IMMUTABLE" != 'true' ]]; then
      cleanup_guidance "release state is invalid"
      return
    fi

    cleanup_guidance "release is no longer a mutable Draft"
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

ARCHIVE_DIGEST="$(sha256_digest_for_file "$ARCHIVE")"
CHECKSUMS_DIGEST="$(sha256_digest_for_file "$CHECKSUMS")"
EVIDENCE_DIGEST="$(sha256_digest_for_file "$EVIDENCE")"

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

# Capture object identity from the same successful create response. A follow-up
# tag lookup cannot establish which Release object this run actually created.
if ! CREATED_RELEASE_ID="$(gh api --method POST \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  "repos/$GITHUB_REPOSITORY/releases" \
  -f tag_name="$TAG" \
  -f target_commitish="$RUN_HEAD_SHA" \
  -f name="SchneeGlass ${RELEASE_VERSION}" \
  -F draft=true \
  -F prerelease=false \
  -F generate_release_notes=true \
  --jq '.id')"; then
  fail "unable to create draft release and capture its identity; remote state may be ambiguous and requires manual reconciliation"
fi
CREATED_RELEASE=true
[[ "$CREATED_RELEASE_ID" =~ ^[1-9][0-9]*$ ]] \
  || fail "created draft release identity is invalid"
RUN_OWNED_RELEASE_API="repos/$GITHUB_REPOSITORY/releases/$CREATED_RELEASE_ID"

if ! RUN_OWNED_RELEASE_ID="$(gh api "$RUN_OWNED_RELEASE_API" --jq '.id')"; then
  fail "unable to verify run-owned draft release identity"
fi
[[ "$RUN_OWNED_RELEASE_ID" =~ ^[1-9][0-9]*$ ]] \
  || fail "run-owned draft release identity is invalid"
[[ "$RUN_OWNED_RELEASE_ID" == "$CREATED_RELEASE_ID" ]] \
  || fail "run-owned draft release identity does not match create response"

if ! OBSERVED_CREATED_RELEASE_ID="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json databaseId \
  --jq '.databaseId')"; then
  fail "unable to verify created draft release identity"
fi
[[ "$OBSERVED_CREATED_RELEASE_ID" =~ ^[1-9][0-9]*$ ]] \
  || fail "observed created draft release identity is invalid"
[[ "$OBSERVED_CREATED_RELEASE_ID" == "$CREATED_RELEASE_ID" ]] \
  || fail "created draft release identity changed immediately after creation"

if ! IS_DRAFT="$(gh api "$RUN_OWNED_RELEASE_API" --jq '.draft')"; then
  fail "unable to verify run-owned draft release state after creation"
fi
[[ "$IS_DRAFT" == 'true' ]] || fail "release was not created as draft"

if ! RELEASE_TARGET="$(gh api "$RUN_OWNED_RELEASE_API" --jq '.target_commitish')"; then
  fail "unable to verify run-owned draft release target after creation"
fi
[[ "$RELEASE_TARGET" == "$RUN_HEAD_SHA" ]] \
  || fail "draft release target mismatch: expected $RUN_HEAD_SHA, got $RELEASE_TARGET"

upload_release_asset_by_id "$ARCHIVE" "$ARCHIVE_NAME" 'application/zip'
upload_release_asset_by_id "$CHECKSUMS" 'SHA256SUMS' 'text/plain'
upload_release_asset_by_id "$EVIDENCE" 'RELEASE_EVIDENCE.txt' 'text/plain'

if ! ASSET_NAMES="$(gh api "$RUN_OWNED_RELEASE_API" --jq '.assets[].name')"; then
  fail "unable to enumerate run-owned draft release assets"
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

FINAL_PUBLISHED_TAGS="$CANDIDATE_DIR/final-published-release-tags.txt"
FINAL_HISTORY_DIR="$CANDIDATE_DIR/final-published-build-history"
rm -rf "$FINAL_HISTORY_DIR"
mkdir -p "$FINAL_HISTORY_DIR"

if ! gh api --paginate "repos/$GITHUB_REPOSITORY/releases?per_page=100" \
  --jq '.[] | select(.draft == false) | .tag_name' \
  > "$FINAL_PUBLISHED_TAGS"; then
  fail "failed to enumerate public release history before publication"
fi

FINAL_HISTORY_INDEX=0
while IFS= read -r PUBLISHED_TAG; do
  [[ -n "$PUBLISHED_TAG" ]] || continue
  FINAL_HISTORY_INDEX=$((FINAL_HISTORY_INDEX + 1))
  FINAL_RELEASE_HISTORY_DIR="$FINAL_HISTORY_DIR/$FINAL_HISTORY_INDEX"
  mkdir -p "$FINAL_RELEASE_HISTORY_DIR"

  gh release download "$PUBLISHED_TAG" \
    --repo "$GITHUB_REPOSITORY" \
    --pattern 'RELEASE_EVIDENCE.txt' \
    --dir "$FINAL_RELEASE_HISTORY_DIR" \
    || fail "public release $PUBLISHED_TAG is missing readable RELEASE_EVIDENCE.txt before publication"

  test -f "$FINAL_RELEASE_HISTORY_DIR/RELEASE_EVIDENCE.txt" \
    || fail "public release $PUBLISHED_TAG did not yield RELEASE_EVIDENCE.txt before publication"
done < "$FINAL_PUBLISHED_TAGS"

bash Scripts/verify-release-build-history.sh "$EVIDENCE" "$FINAL_HISTORY_DIR"

PREPUBLICATION_RUN_OWNED_RELEASE_JSON="$CANDIDATE_DIR/prepublication-run-owned-release.json"
if ! gh api "$RUN_OWNED_RELEASE_API" > "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON"; then
  fail "unable to fetch run-owned draft release snapshot before publication"
fi
jq -e '
  type == "object" and
  (.id | type == "number" and . > 0 and . == floor) and
  (.draft | type == "boolean") and
  (.prerelease | type == "boolean") and
  (.target_commitish | type == "string") and
  (.assets | type == "array" and all(.[]; type == "object" and (.name | type == "string") and (.digest | type == "string")))
' "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON" >/dev/null \
  || fail "run-owned draft release snapshot is malformed before publication"

PREPUBLICATION_RUN_OWNED_RELEASE_ID="$(jq -r '.id | tostring' "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON")"
PREPUBLICATION_IS_DRAFT="$(jq -r '.draft' "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON")"
PREPUBLICATION_IS_PRERELEASE="$(jq -r '.prerelease' "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON")"
PREPUBLICATION_RELEASE_TARGET="$(jq -r '.target_commitish' "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON")"
PREPUBLICATION_ASSET_NAMES="$(jq -r '.assets[].name' "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON")"

[[ "$PREPUBLICATION_RUN_OWNED_RELEASE_ID" == "$CREATED_RELEASE_ID" ]] \
  || fail "run-owned draft release identity changed before publication"
[[ "$PREPUBLICATION_IS_DRAFT" == 'true' ]] \
  || fail "release is no longer a Draft before publication"
[[ "$PREPUBLICATION_IS_PRERELEASE" == 'false' ]] \
  || fail "release became a prerelease before stable publication"
[[ "$PREPUBLICATION_RELEASE_TARGET" =~ ^[0-9a-f]{40}$ ]] \
  || fail "draft release target returned an invalid commit SHA before publication"
[[ "$PREPUBLICATION_RELEASE_TARGET" == "$RUN_HEAD_SHA" ]] \
  || fail "draft release target changed before publication"
release_asset_set_is_exact "$PREPUBLICATION_ASSET_NAMES" \
  || fail "draft release asset set changed before publication"
release_asset_digests_match_expected "$PREPUBLICATION_RUN_OWNED_RELEASE_JSON" \
  || fail "draft release asset digests do not match the validated candidate before publication"

if ! PREPUBLICATION_RELEASE_ID="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json databaseId \
  --jq '.databaseId')"; then
  fail "unable to verify draft release identity before publication"
fi
[[ "$PREPUBLICATION_RELEASE_ID" =~ ^[1-9][0-9]*$ ]] \
  || fail "draft release identity is invalid before publication"
[[ "$PREPUBLICATION_RELEASE_ID" == "$CREATED_RELEASE_ID" ]] \
  || fail "draft release identity changed before publication"

# Address the mutation by the captured object identity so a same-tag replacement
# cannot redirect this run's Draft -> public transition after the final ID proof.
if ! gh api --method PATCH \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  "repos/$GITHUB_REPOSITORY/releases/$CREATED_RELEASE_ID" \
  -F draft=false \
  -F prerelease=false \
  -f make_latest=true \
  >/dev/null; then
  fail "unable to publish run-owned Release by identity; publication state is ambiguous and requires manual reconciliation"
fi
PUBLICATION_COMMAND_SUCCEEDED=true

PUBLISHED_RUN_OWNED_RELEASE_JSON="$CANDIDATE_DIR/published-run-owned-release.json"
if ! gh api "$RUN_OWNED_RELEASE_API" > "$PUBLISHED_RUN_OWNED_RELEASE_JSON"; then
  fail "unable to fetch run-owned published release snapshot; publication state is ambiguous and requires manual reconciliation"
fi
jq -e '
  type == "object" and
  (.id | type == "number" and . > 0 and . == floor) and
  (.draft | type == "boolean") and
  (.immutable | type == "boolean") and
  (.target_commitish | type == "string") and
  (.assets | type == "array" and all(.[]; type == "object" and (.name | type == "string") and (.digest | type == "string")))
' "$PUBLISHED_RUN_OWNED_RELEASE_JSON" >/dev/null \
  || fail "run-owned published release snapshot is malformed; publication state is ambiguous and requires manual reconciliation"

PUBLISHED_RUN_OWNED_RELEASE_ID="$(jq -r '.id | tostring' "$PUBLISHED_RUN_OWNED_RELEASE_JSON")"
IS_DRAFT="$(jq -r '.draft' "$PUBLISHED_RUN_OWNED_RELEASE_JSON")"
IS_IMMUTABLE="$(jq -r '.immutable' "$PUBLISHED_RUN_OWNED_RELEASE_JSON")"
PUBLISHED_RELEASE_TARGET="$(jq -r '.target_commitish' "$PUBLISHED_RUN_OWNED_RELEASE_JSON")"
PUBLISHED_ASSET_NAMES="$(jq -r '.assets[].name' "$PUBLISHED_RUN_OWNED_RELEASE_JSON")"

[[ "$PUBLISHED_RUN_OWNED_RELEASE_ID" == "$CREATED_RELEASE_ID" ]] \
  || fail "run-owned published release identity does not match create response; publication state is ambiguous and requires manual reconciliation"

if [[ "$IS_DRAFT" != 'false' ]]; then
  if [[ "$IS_DRAFT" == 'true' ]]; then
    PUBLICATION_COMMAND_SUCCEEDED=false
    fail "release did not become public"
  fi
  fail "published release returned invalid draft state; publication state is ambiguous and requires manual reconciliation"
fi

if [[ "$IS_IMMUTABLE" == 'false' ]]; then
  fail "published release is mutable; no automatic remote cleanup was attempted; manual reconciliation required for $TAG (captured release ID $CREATED_RELEASE_ID); enable repository release immutability before retrying"
fi

[[ "$IS_IMMUTABLE" == 'true' ]] \
  || fail "published release returned invalid immutability state; publication state is ambiguous and requires manual reconciliation"
release_asset_set_is_exact "$PUBLISHED_ASSET_NAMES" \
  || fail "published release asset set does not exactly match expected public assets; publication state is ambiguous and requires manual reconciliation"
release_asset_digests_match_expected "$PUBLISHED_RUN_OWNED_RELEASE_JSON" \
  || fail "published release asset digests do not match the validated candidate; publication state is ambiguous and requires manual reconciliation"
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

if ! PUBLISHED_RELEASE_ID="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json databaseId \
  --jq '.databaseId')"; then
  fail "unable to verify published release identity; publication state is ambiguous and requires manual reconciliation"
fi
[[ "$PUBLISHED_RELEASE_ID" =~ ^[1-9][0-9]*$ ]] \
  || fail "published release identity is invalid; publication state is ambiguous and requires manual reconciliation"
[[ "$PUBLISHED_RELEASE_ID" == "$CREATED_RELEASE_ID" ]] \
  || fail "published release identity does not match run-created Release; publication state is ambiguous and requires manual reconciliation"

CREATED_RELEASE=false
trap - EXIT
rm -rf "$CANDIDATE_DIR"

echo "Published immutable release $TAG from candidate run $CANDIDATE_RUN_ID ($RUN_HEAD_SHA)."
