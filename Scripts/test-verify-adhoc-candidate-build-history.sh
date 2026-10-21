#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ARTIFACT="$TMP/candidate"
HISTORY="$TMP/published"
mkdir -p "$ARTIFACT" "$HISTORY/one" "$HISTORY/two"

VERSION='0.2.0'
BUILD='3'
SOURCE_SHA='0123456789abcdef0123456789abcdef01234567'
ZIP="SchneeGlass-$VERSION-adhoc-candidate.zip"

printf 'synthetic ZIP content, not a Mac app\n' > "$ARTIFACT/$ZIP"
for file in README.txt CODESIGN_DETAILS.txt ENTITLEMENTS.plist; do
  printf 'synthetic fixture\n' > "$ARTIFACT/$file"
done
(cd "$ARTIFACT" && shasum -a 256 "$ZIP" > SHA256SUMS)

cat > "$ARTIFACT/BUILD_INFO.txt" <<EOF
version=$VERSION
build=$BUILD
source_commit=$SOURCE_SHA
source_branch=main
code_signature=adhoc
apple_developer_id_signed=false
apple_notarized=false
minimum_macos=15.0
executable_info=synthetic-test
distribution=github-adhoc-candidate
EOF

evidence() {
  local directory="$1" build="$2"
  printf 'schema_version=1\nbundle_build=%s\n' "$build" > "$directory/RELEASE_EVIDENCE.txt"
}

evidence "$HISTORY/one" 1
evidence "$HISTORY/two" 2

verify() {
  bash Scripts/verify-adhoc-candidate-build-history.sh \
    "$ARTIFACT" "$VERSION" "$BUILD" "$SOURCE_SHA" "$HISTORY"
}

reject() {
  local name="$1" message="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    echo "Invalid monotonic history accepted: $name" >&2
    exit 1
  fi
  [[ "$output" == *"$message"* ]] || {
    echo "Unexpected error for $name: $output" >&2
    exit 1
  }
}

verify >/dev/null
evidence "$HISTORY/two" 3
reject 'reused build' 'candidate build is not greater than the published build history' verify
evidence "$HISTORY/two" 4
reject 'regressed build' 'candidate build is not greater than the published build history' verify
evidence "$HISTORY/two" 'invalid'
reject 'invalid public build history' 'candidate build is not greater than the published build history' verify
evidence "$HISTORY/two" 2

printf 'modified after manifest\n' >> "$ARTIFACT/$ZIP"
reject 'tampered candidate ZIP' 'candidate artifact metadata or SHA-256 validation failed' verify
printf 'synthetic ZIP content, not a Mac app\n' > "$ARTIFACT/$ZIP"

sed -i.bak 's/build=3/build=4/' "$ARTIFACT/BUILD_INFO.txt"
reject 'candidate metadata build mismatch' 'candidate artifact metadata or SHA-256 validation failed' verify
mv "$ARTIFACT/BUILD_INFO.txt.bak" "$ARTIFACT/BUILD_INFO.txt"

reject 'source SHA mismatch' 'candidate artifact metadata or SHA-256 validation failed' \
  bash Scripts/verify-adhoc-candidate-build-history.sh \
    "$ARTIFACT" "$VERSION" "$BUILD" '89abcdef0123456789abcdef0123456789abcdef' "$HISTORY"

ln -s "$HISTORY/one/RELEASE_EVIDENCE.txt" "$HISTORY/linked.txt"
reject 'symlink ignored by underlying find' 'trusted history contains a symlink' verify
rm "$HISTORY/linked.txt"

ln -s "$HISTORY" "$TMP/symlink-history"
reject 'symlink history root' 'trusted history must be an existing real directory' \
  bash Scripts/verify-adhoc-candidate-build-history.sh \
    "$ARTIFACT" "$VERSION" "$BUILD" "$SOURCE_SHA" "$TMP/symlink-history"

reject 'missing history directory' 'trusted history must be an existing real directory' \
  bash Scripts/verify-adhoc-candidate-build-history.sh \
    "$ARTIFACT" "$VERSION" "$BUILD" "$SOURCE_SHA" "$TMP/missing"

reject 'oversized numeric build' 'candidate build must be a positive decimal with at most 9 digits' \
  bash Scripts/verify-adhoc-candidate-build-history.sh \
    "$ARTIFACT" "$VERSION" '999999999999999999999999999' "$SOURCE_SHA" "$HISTORY"

reject 'build zero' 'candidate build must be a positive decimal with at most 9 digits' \
  bash Scripts/verify-adhoc-candidate-build-history.sh \
    "$ARTIFACT" "$VERSION" '0' "$SOURCE_SHA" "$HISTORY"

reject 'missing argument' 'usage:' \
  bash Scripts/verify-adhoc-candidate-build-history.sh \
    "$ARTIFACT" "$VERSION" "$BUILD" "$SOURCE_SHA"

# An empty but *complete* materialized history is the supported first-publication case.
mkdir -p "$TMP/empty-history"
bash Scripts/verify-adhoc-candidate-build-history.sh \
  "$ARTIFACT" "$VERSION" "$BUILD" "$SOURCE_SHA" "$TMP/empty-history" >/dev/null

verify >/dev/null
echo 'Ad-hoc monotonic build-history fixtures passed'
