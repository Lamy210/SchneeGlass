#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Legacy release build-info validation failed: $*" >&2
  exit 1
}

MANIFEST="${1:-}"
TAG="${2:-}"
RELEASE_TARGET="${3:-}"
BUILD_INFO="${4:-}"

[[ -n "$MANIFEST" && -f "$MANIFEST" ]] || fail "legacy release manifest is required"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "release tag must be vX.Y.Z"
[[ "$RELEASE_TARGET" =~ ^[0-9a-f]{40}$ ]] || fail "release target must be a 40-character lowercase commit SHA"
[[ -n "$BUILD_INFO" && -f "$BUILD_INFO" ]] || fail "BUILD_INFO.txt is required"

EXPECTED_TARGET=''
EXPECTED_VERSION=''
EXPECTED_BUILD=''
EXPECTED_DISTRIBUTION=''
EXPECTED_DIGEST=''
MATCH_COUNT=0

while IFS=$'\t' read -r row_tag row_target row_version row_build row_distribution row_digest extra; do
  [[ -n "$row_tag" ]] || continue
  [[ "$row_tag" == \#* ]] && continue

  [[ -z "${extra:-}" ]] || fail "legacy manifest row has unexpected extra fields: $row_tag"
  [[ "$row_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "legacy manifest tag is invalid: $row_tag"
  [[ "$row_target" =~ ^[0-9a-f]{40}$ ]] || fail "legacy manifest target is invalid for $row_tag"
  [[ "$row_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "legacy manifest version is invalid for $row_tag"
  [[ "$row_build" =~ ^[1-9][0-9]*$ ]] || fail "legacy manifest build is invalid for $row_tag"
  [[ "$row_distribution" == 'github-unsigned' || "$row_distribution" == 'github-adhoc' ]] \
    || fail "legacy manifest distribution is invalid for $row_tag"
  [[ "$row_digest" =~ ^[0-9a-f]{64}$ ]] || fail "legacy manifest BUILD_INFO digest is invalid for $row_tag"
  [[ "v$row_version" == "$row_tag" ]] || fail "legacy manifest tag/version mismatch for $row_tag"

  if [[ "$row_tag" == "$TAG" ]]; then
    MATCH_COUNT=$((MATCH_COUNT + 1))
    EXPECTED_TARGET="$row_target"
    EXPECTED_VERSION="$row_version"
    EXPECTED_BUILD="$row_build"
    EXPECTED_DISTRIBUTION="$row_distribution"
    EXPECTED_DIGEST="$row_digest"
  fi
done < "$MANIFEST"

[[ "$MATCH_COUNT" -eq 1 ]] || fail "release tag is not exactly once in legacy manifest: $TAG"
[[ "$RELEASE_TARGET" == "$EXPECTED_TARGET" ]] \
  || fail "release target mismatch for $TAG"

ACTUAL_DIGEST="$(shasum -a 256 "$BUILD_INFO" | awk '{print $1}')"
[[ "$ACTUAL_DIGEST" =~ ^[0-9a-f]{64}$ ]] || fail "unable to compute BUILD_INFO SHA-256"
[[ "$ACTUAL_DIGEST" == "$EXPECTED_DIGEST" ]] || fail "BUILD_INFO digest mismatch for $TAG"

read_single_value() {
  local key="$1"
  local count=''
  local grep_status=0

  set +e
  count="$(grep -c "^${key}=" "$BUILD_INFO")"
  grep_status=$?
  set -e

  case "$grep_status" in
    0)
      ;;
    1)
      count='0'
      ;;
    *)
      fail "unable to enumerate $key in BUILD_INFO.txt (grep status $grep_status)"
      ;;
  esac

  [[ "$count" =~ ^[0-9]+$ ]] || fail "BUILD_INFO key count is not numeric for $key"
  [[ "$count" == '1' ]] || fail "BUILD_INFO.txt must contain exactly one $key"
  sed -n "s/^${key}=//p" "$BUILD_INFO"
}

VERSION="$(read_single_value version)"
BUILD="$(read_single_value build)"
SOURCE_COMMIT="$(read_single_value source_commit)"
DISTRIBUTION="$(read_single_value distribution)"
DEVELOPER_ID_SIGNED="$(read_single_value apple_developer_id_signed)"
NOTARIZED="$(read_single_value apple_notarized)"

[[ "$VERSION" == "$EXPECTED_VERSION" ]] || fail "BUILD_INFO version mismatch for $TAG"
[[ "$BUILD" == "$EXPECTED_BUILD" ]] || fail "BUILD_INFO build mismatch for $TAG"
[[ "$SOURCE_COMMIT" == "$EXPECTED_TARGET" ]] || fail "BUILD_INFO source_commit mismatch for $TAG"
[[ "$DISTRIBUTION" == "$EXPECTED_DISTRIBUTION" ]] || fail "BUILD_INFO distribution mismatch for $TAG"
[[ "$DEVELOPER_ID_SIGNED" == 'false' ]] || fail "legacy release unexpectedly claims Developer ID signing"
[[ "$NOTARIZED" == 'false' ]] || fail "legacy release unexpectedly claims notarization"

printf '%s\n' "$BUILD"
