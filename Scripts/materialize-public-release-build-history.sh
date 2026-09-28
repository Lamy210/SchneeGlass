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
command -v jq >/dev/null 2>&1 || fail "jq is required"

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

  RELEASE_SNAPSHOT="$RELEASE_HISTORY_DIR/release.json"
  if ! gh release view "$PUBLISHED_TAG" \
    --repo "$REPOSITORY" \
    --json targetCommitish,assets \
    > "$RELEASE_SNAPSHOT"; then
    fail "unable to read public release metadata for $PUBLISHED_TAG"
  fi
  jq -e '
    type == "object" and
    (.targetCommitish | type == "string") and
    (.assets | type == "array" and all(.[]; type == "object" and (.name | type == "string")))
  ' "$RELEASE_SNAPSHOT" >/dev/null \
    || fail "public release metadata is malformed for $PUBLISHED_TAG"

  EVIDENCE_COUNT="$(jq '[.assets[] | select(.name == "RELEASE_EVIDENCE.txt")] | length' "$RELEASE_SNAPSHOT")"
  BUILD_INFO_COUNT="$(jq '[.assets[] | select(.name == "BUILD_INFO.txt")] | length' "$RELEASE_SNAPSHOT")"
  [[ "$EVIDENCE_COUNT" =~ ^[0-9]+$ && "$BUILD_INFO_COUNT" =~ ^[0-9]+$ ]] \
    || fail "public release asset counts are invalid for $PUBLISHED_TAG"
  [[ "$EVIDENCE_COUNT" -le 1 ]] \
    || fail "public release has duplicate RELEASE_EVIDENCE.txt assets: $PUBLISHED_TAG"

  if [[ "$EVIDENCE_COUNT" -eq 1 ]]; then
    if ! gh release download "$PUBLISHED_TAG" \
      --repo "$REPOSITORY" \
      --pattern 'RELEASE_EVIDENCE.txt' \
      --dir "$RELEASE_HISTORY_DIR"; then
      fail "public release $PUBLISHED_TAG declares RELEASE_EVIDENCE.txt but it could not be downloaded"
    fi
    [[ -f "$RELEASE_HISTORY_DIR/RELEASE_EVIDENCE.txt" ]] \
      || fail "public release $PUBLISHED_TAG declared evidence download success without RELEASE_EVIDENCE.txt"
    continue
  fi

  [[ "$BUILD_INFO_COUNT" -eq 1 ]] \
    || fail "pre-evidence public release must contain exactly one BUILD_INFO.txt: $PUBLISHED_TAG"

  RELEASE_TARGET="$(jq -r '.targetCommitish' "$RELEASE_SNAPSHOT")"
  [[ "$RELEASE_TARGET" =~ ^[0-9a-f]{40}$ ]] \
    || fail "legacy release target is not an exact commit SHA for $PUBLISHED_TAG"

  if ! gh release download "$PUBLISHED_TAG" \
    --repo "$REPOSITORY" \
    --pattern 'BUILD_INFO.txt' \
    --dir "$RELEASE_HISTORY_DIR"; then
    fail "legacy public release BUILD_INFO.txt could not be downloaded: $PUBLISHED_TAG"
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
