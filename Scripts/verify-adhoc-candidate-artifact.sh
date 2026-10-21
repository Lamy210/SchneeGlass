#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "Ad-hoc candidate artifact verification failed: $*" >&2
  exit 1
}

[[ "$#" -eq 4 ]] || fail 'usage: verify-adhoc-candidate-artifact.sh <artifact-directory> <expected-version> <expected-build> <expected-source-sha>'

ARTIFACT_DIR="$1"
EXPECTED_VERSION="$2"
EXPECTED_BUILD="$3"
EXPECTED_SHA="$4"

[[ -d "$ARTIFACT_DIR" && ! -L "$ARTIFACT_DIR" ]] || fail 'artifact directory must be a real directory'
[[ "$EXPECTED_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'expected version must be strict X.Y.Z'
[[ "$EXPECTED_BUILD" =~ ^[1-9][0-9]*$ ]] || fail 'expected build must be a positive decimal integer'
[[ "$EXPECTED_SHA" =~ ^[0-9a-f]{40}$ ]] || fail 'expected source SHA must be lowercase 40-hex'

ARCHIVE_NAME="SchneeGlass-$EXPECTED_VERSION-adhoc-candidate.zip"
for item in "$ARCHIVE_NAME" BUILD_INFO.txt SHA256SUMS README.txt CODESIGN_DETAILS.txt ENTITLEMENTS.plist; do
  [[ -f "$ARTIFACT_DIR/$item" && ! -L "$ARTIFACT_DIR/$item" && -s "$ARTIFACT_DIR/$item" ]] \
    || fail "missing, empty, or symbolic-link artifact: $item"
done

# Avoid Bash 4+ associative arrays: this verifier also runs on macOS (Bash 3.2).
seen_keys='|'
count=0
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" == *=* ]] || fail 'malformed BUILD_INFO line'
  key="${line%%=*}"
  value="${line#*=}"
  case "$key" in
    version|build|source_commit|source_branch|code_signature|apple_developer_id_signed|apple_notarized|minimum_macos|executable_info|distribution) ;;
    *) fail "unknown BUILD_INFO field: $key" ;;
  esac
  [[ "$seen_keys" != *"|$key|"* ]] || fail "duplicate BUILD_INFO field: $key"
  [[ -n "$value" ]] || fail "empty BUILD_INFO field: $key"
  seen_keys+="$key|"

  case "$key" in
    version) [[ "$value" == "$EXPECTED_VERSION" ]] || fail 'version mismatch' ;;
    build) [[ "$value" == "$EXPECTED_BUILD" ]] || fail 'build mismatch' ;;
    source_commit) [[ "$value" == "$EXPECTED_SHA" ]] || fail 'source commit mismatch' ;;
    source_branch) [[ "$value" == 'main' ]] || fail 'source branch must be main' ;;
    code_signature) [[ "$value" == 'adhoc' ]] || fail 'candidate must be ad-hoc signed' ;;
    apple_developer_id_signed) [[ "$value" == 'false' ]] || fail 'Developer ID signing is not allowed' ;;
    apple_notarized) [[ "$value" == 'false' ]] || fail 'Apple notarization is not allowed' ;;
    minimum_macos) [[ "$value" == '15.0' ]] || fail 'minimum macOS baseline mismatch' ;;
    distribution) [[ "$value" == 'github-adhoc-candidate' ]] || fail 'unexpected distribution metadata' ;;
    executable_info) : ;;
  esac
  ((count += 1))
done < "$ARTIFACT_DIR/BUILD_INFO.txt"

[[ "$count" -eq 10 ]] || fail "BUILD_INFO must have exactly 10 fields (found $count)"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/verify-release-checksum-manifest.sh" "$ARTIFACT_DIR" "$ARCHIVE_NAME" >/dev/null \
  || fail 'archive checksum verification failed'

echo "Ad-hoc candidate artifact metadata and checksum verified: version=$EXPECTED_VERSION build=$EXPECTED_BUILD sha=$EXPECTED_SHA"
