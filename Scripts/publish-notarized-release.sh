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
CREATED_DRAFT=false

cleanup() {
  set +e
  rm -rf "$CANDIDATE_DIR"

  if [[ "$CREATED_DRAFT" == 'true' ]]; then
    IS_DRAFT="$(gh release view "$TAG" \
      --repo "$GITHUB_REPOSITORY" \
      --json isDraft \
      --jq '.isDraft' 2>/dev/null || true)"

    if [[ "$IS_DRAFT" == 'true' ]]; then
      gh release delete "$TAG" \
        --repo "$GITHUB_REPOSITORY" \
        --cleanup-tag \
        --yes >/dev/null 2>&1 || true
    elif ! gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
      if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
        git push origin ":refs/tags/$TAG" >/dev/null 2>&1 || true
      fi
    fi
  fi
}
trap cleanup EXIT

rm -rf "$CANDIDATE_DIR"
mkdir -p "$CANDIDATE_DIR"

RUN_NAME="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CANDIDATE_RUN_ID" --jq '.name')"
RUN_EVENT="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CANDIDATE_RUN_ID" --jq '.event')"
RUN_STATUS="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CANDIDATE_RUN_ID" --jq '.status')"
RUN_CONCLUSION="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CANDIDATE_RUN_ID" --jq '.conclusion')"
RUN_BRANCH="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CANDIDATE_RUN_ID" --jq '.head_branch')"
RUN_HEAD_SHA="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$CANDIDATE_RUN_ID" --jq '.head_sha')"

[[ "$RUN_NAME" == 'Production Release Candidate' ]] \
  || fail "candidate run belongs to unexpected workflow: $RUN_NAME"
[[ "$RUN_EVENT" == 'workflow_dispatch' ]] \
  || fail "candidate run must be workflow_dispatch"
[[ "$RUN_STATUS" == 'completed' && "$RUN_CONCLUSION" == 'success' ]] \
  || fail "candidate run is not completed successfully"
[[ "$RUN_BRANCH" == 'main' ]] \
  || fail "candidate run was not built from main"
[[ "$RUN_HEAD_SHA" =~ ^[0-9a-f]{40}$ ]] \
  || fail "candidate run returned an invalid head SHA"

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

grep -Fx "version=$RELEASE_VERSION" "$EVIDENCE" >/dev/null \
  || fail "candidate evidence version mismatch"
grep -Fx 'notarization_status=Accepted' "$EVIDENCE" >/dev/null \
  || fail "candidate is not notarization Accepted"
grep -Fx 'codesign=verified' "$EVIDENCE" >/dev/null \
  || fail "candidate codesign evidence is missing"
grep -Fx 'stapler=validated' "$EVIDENCE" >/dev/null \
  || fail "candidate stapler evidence is missing"
grep -Fx 'gatekeeper=accepted' "$EVIDENCE" >/dev/null \
  || fail "candidate Gatekeeper evidence is missing"
grep -Fx "commit_sha=$RUN_HEAD_SHA" "$EVIDENCE" >/dev/null \
  || fail "candidate source commit evidence mismatch"

grep -E "^[0-9a-fA-F]{64}  ${ARCHIVE_NAME}$" "$CHECKSUMS" >/dev/null \
  || fail "SHA256SUMS does not contain the expected release archive"
(
  cd "$CANDIDATE_DIR"
  shasum -a 256 -c SHA256SUMS
)

git fetch origin main --tags --force
git cat-file -e "$RUN_HEAD_SHA^{commit}" \
  || fail "candidate source commit is not available in repository history"
git merge-base --is-ancestor "$RUN_HEAD_SHA" origin/main \
  || fail "candidate source commit is not an ancestor of current main"

if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "release tag already exists: $TAG"
fi

if gh release view "$TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
  fail "GitHub Release already exists: $TAG"
fi

CREATED_DRAFT=true
gh release create "$TAG" \
  "$ARCHIVE" \
  "$CHECKSUMS" \
  "$EVIDENCE" \
  --repo "$GITHUB_REPOSITORY" \
  --target "$RUN_HEAD_SHA" \
  --title "SchneeGlass ${RELEASE_VERSION}" \
  --generate-notes \
  --draft

IS_DRAFT="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json isDraft \
  --jq '.isDraft')"
[[ "$IS_DRAFT" == 'true' ]] || fail "release was not created as draft"

ASSET_NAMES="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json assets \
  --jq '.assets[].name')"
printf '%s\n' "$ASSET_NAMES" | grep -Fx "$ARCHIVE_NAME" >/dev/null \
  || fail "draft release is missing the app archive"
printf '%s\n' "$ASSET_NAMES" | grep -Fx 'SHA256SUMS' >/dev/null \
  || fail "draft release is missing SHA256SUMS"
printf '%s\n' "$ASSET_NAMES" | grep -Fx 'RELEASE_EVIDENCE.txt' >/dev/null \
  || fail "draft release is missing RELEASE_EVIDENCE.txt"

gh release edit "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --draft=false \
  --latest

IS_DRAFT="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json isDraft \
  --jq '.isDraft')"
[[ "$IS_DRAFT" == 'false' ]] || fail "release did not become public"

IS_IMMUTABLE="$(gh release view "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --json isImmutable \
  --jq '.isImmutable')"
if [[ "$IS_IMMUTABLE" != 'true' ]]; then
  gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft
  fail "published release is not immutable; enable repository release immutability before retrying"
fi

CREATED_DRAFT=false
trap - EXIT
rm -rf "$CANDIDATE_DIR"

echo "Published immutable release $TAG from candidate run $CANDIDATE_RUN_ID ($RUN_HEAD_SHA)."
