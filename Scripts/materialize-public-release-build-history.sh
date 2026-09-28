#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Public release build-history materialization failed: $*" >&2
  exit 1
}

REPOSITORY="${1:-}"
TAGS_FILE="${2:-}"
HISTORY_DIR="${3:-}"
LEGACY_MANIFEST="${4:-docs/release-history/legacy-public-releases.tsv}"

[[ -n "$REPOSITORY" ]] || fail "repository is required"
[[ -n "$TAGS_FILE" && -f "$TAGS_FILE" ]] || fail "published release tags file is required"
[[ -n "$HISTORY_DIR" ]] || fail "history directory is required"
[[ -f "$LEGACY_MANIFEST" ]] || fail "legacy release manifest is missing: $LEGACY_MANIFEST"
command -v gh >/dev/null 2>&1 || fail "gh CLI is required"

mkdir -p "$HISTORY_DIR"

HISTORY_INDEX=0
while IFS= read -r PUBLISHED_TAG; do
  [[ -n "$PUBLISHED_TAG" ]] || continue
  [[ "$PUBLISHED_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail "public release tag is not vX.Y.Z: $PUBLISHED_TAG"

  HISTORY_INDEX=$((HISTORY_INDEX + 1))
  RELEASE_HISTORY_DIR="$HISTORY_DIR/$HISTORY_INDEX"
  rm -rf "$RELEASE_HISTORY_DIR"
  mkdir -p "$RELEASE_HISTORY_DIR"

  set +e
  gh release download "$PUBLISHED_TAG" \
    --repo "$REPOSITORY" \
    --pattern 'RELEASE_EVIDENCE.txt' \
    --dir "$RELEASE_HISTORY_DIR"
  EVIDENCE_DOWNLOAD_STATUS=$?
  set -e

  if [[ "$EVIDENCE_DOWNLOAD_STATUS" -eq 0 ]]; then
    [[ -f "$RELEASE_HISTORY_DIR/RELEASE_EVIDENCE.txt" ]] \
      || fail "public release $PUBLISHED_TAG reported evidence download success without RELEASE_EVIDENCE.txt"
    continue
  fi

  rm -f "$RELEASE_HISTORY_DIR/RELEASE_EVIDENCE.txt"

  RELEASE_TARGET=''
  if ! RELEASE_TARGET="$(gh release view "$PUBLISHED_TAG" \
    --repo "$REPOSITORY" \
    --json targetCommitish \
    --jq '.targetCommitish')"; then
    fail "unable to read release target for legacy release $PUBLISHED_TAG"
  fi
  [[ "$RELEASE_TARGET" =~ ^[0-9a-f]{40}$ ]] \
    || fail "legacy release target is not an exact commit SHA for $PUBLISHED_TAG"

  if ! gh release download "$PUBLISHED_TAG" \
    --repo "$REPOSITORY" \
    --pattern 'BUILD_INFO.txt' \
    --dir "$RELEASE_HISTORY_DIR"; then
    fail "public release $PUBLISHED_TAG has neither readable RELEASE_EVIDENCE.txt nor readable legacy BUILD_INFO.txt"
  fi

  BUILD_INFO="$RELEASE_HISTORY_DIR/BUILD_INFO.txt"
  [[ -f "$BUILD_INFO" ]] \
    || fail "legacy release $PUBLISHED_TAG did not yield BUILD_INFO.txt"

  LEGACY_BUILD=''
  if ! LEGACY_BUILD="$(bash Scripts/verify-legacy-release-build-info.sh \
    "$LEGACY_MANIFEST" \
    "$PUBLISHED_TAG" \
    "$RELEASE_TARGET" \
    "$BUILD_INFO")"; then
    fail "legacy release verification failed for $PUBLISHED_TAG"
  fi
  [[ "$LEGACY_BUILD" =~ ^[1-9][0-9]*$ ]] \
    || fail "legacy release verifier returned an invalid build for $PUBLISHED_TAG"

  cat > "$RELEASE_HISTORY_DIR/RELEASE_EVIDENCE.txt" <<EOF
schema_version=1
bundle_build=$LEGACY_BUILD
EOF
done < "$TAGS_FILE"
