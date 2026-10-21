#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
ARTIFACT="$FIXTURE/artifact"
mkdir -p "$ARTIFACT"

VERSION='0.2.0'
BUILD='3'
SHA='0123456789abcdef0123456789abcdef01234567'
OTHER_SHA='89abcdef0123456789abcdef0123456789abcdef'
ARCHIVE="SchneeGlass-$VERSION-adhoc-candidate.zip"

printf 'synthetic archive, not a signed application\n' > "$ARTIFACT/$ARCHIVE"
for file in README.txt CODESIGN_DETAILS.txt ENTITLEMENTS.plist; do
  printf 'synthetic fixture\n' > "$ARTIFACT/$file"
done

cat > "$ARTIFACT/BUILD_INFO.txt" <<EOF
version=$VERSION
build=$BUILD
source_commit=$SHA
source_branch=main
code_signature=adhoc
apple_developer_id_signed=false
apple_notarized=false
minimum_macos=15.0
executable_info=Mach-O 64-bit executable x86_64
distribution=github-adhoc-candidate
EOF
cp "$ARTIFACT/BUILD_INFO.txt" "$FIXTURE/original"
(cd "$ARTIFACT" && shasum -a 256 "$ARCHIVE" > SHA256SUMS)
cp "$ARTIFACT/SHA256SUMS" "$FIXTURE/manifest"

verify() {
  bash Scripts/verify-adhoc-candidate-artifact.sh "$ARTIFACT" "$VERSION" "$BUILD" "$SHA"
}
expect_failure() {
  local label="$1" diagnostic="$2"
  shift 2
  local result
  if result="$("$@" 2>&1)"; then
    echo "Invalid fixture was accepted: $label" >&2
    exit 1
  fi
  [[ "$result" == *"$diagnostic"* ]] || {
    echo "Unexpected diagnostic for $label: $result" >&2
    exit 1
  }
}
verify >/dev/null

while IFS='|' read -r before after diagnostic; do
  sed "s/$before/$after/" "$FIXTURE/original" > "$ARTIFACT/BUILD_INFO.txt"
  expect_failure "$after" "$diagnostic" verify
  cp "$FIXTURE/original" "$ARTIFACT/BUILD_INFO.txt"
done <<EOF
version=0.2.0|version=0.2.1|version mismatch
build=3|build=4|build mismatch
source_commit=$SHA|source_commit=$OTHER_SHA|source commit mismatch
source_branch=main|source_branch=release|source branch must be main
code_signature=adhoc|code_signature=none|candidate must be ad-hoc signed
apple_developer_id_signed=false|apple_developer_id_signed=true|Developer ID signing is not allowed
apple_notarized=false|apple_notarized=true|Apple notarization is not allowed
minimum_macos=15.0|minimum_macos=14.0|minimum macOS baseline mismatch
distribution=github-adhoc-candidate|distribution=unknown|unexpected distribution metadata
EOF

printf 'version=0.2.0\n' >> "$ARTIFACT/BUILD_INFO.txt"
expect_failure 'duplicate metadata' 'duplicate BUILD_INFO field: version' verify
cp "$FIXTURE/original" "$ARTIFACT/BUILD_INFO.txt"

printf 'unexpected=true\n' >> "$ARTIFACT/BUILD_INFO.txt"
expect_failure 'unknown metadata' 'unknown BUILD_INFO field: unexpected' verify
cp "$FIXTURE/original" "$ARTIFACT/BUILD_INFO.txt"

printf 'malformed-line\n' >> "$ARTIFACT/BUILD_INFO.txt"
expect_failure 'malformed metadata' 'malformed BUILD_INFO line' verify
cp "$FIXTURE/original" "$ARTIFACT/BUILD_INFO.txt"

sed '/^source_branch=/d' "$FIXTURE/original" > "$ARTIFACT/BUILD_INFO.txt"
expect_failure 'missing metadata' 'BUILD_INFO must have exactly 10 fields' verify
cp "$FIXTURE/original" "$ARTIFACT/BUILD_INFO.txt"

printf 'modified archive\n' >> "$ARTIFACT/$ARCHIVE"
expect_failure 'modified ZIP' 'archive checksum verification failed' verify
printf 'synthetic archive, not a signed application\n' > "$ARTIFACT/$ARCHIVE"

printf 'invalid extra checksum entry\n' >> "$ARTIFACT/SHA256SUMS"
expect_failure 'extra checksum' 'archive checksum verification failed' verify
cp "$FIXTURE/manifest" "$ARTIFACT/SHA256SUMS"

mv "$ARTIFACT/README.txt" "$FIXTURE/README.txt"
ln -s "$FIXTURE/README.txt" "$ARTIFACT/README.txt"
expect_failure 'symlinked artifact' 'missing, empty, or symbolic-link artifact: README.txt' verify
rm "$ARTIFACT/README.txt"
mv "$FIXTURE/README.txt" "$ARTIFACT/README.txt"

expect_failure 'invalid expected version' 'expected version must be strict X.Y.Z' \
  bash Scripts/verify-adhoc-candidate-artifact.sh "$ARTIFACT" 'v0.2.0' "$BUILD" "$SHA"
expect_failure 'invalid expected build' 'expected build must be a positive decimal integer' \
  bash Scripts/verify-adhoc-candidate-artifact.sh "$ARTIFACT" "$VERSION" '0' "$SHA"
expect_failure 'invalid expected SHA' 'expected source SHA must be lowercase 40-hex' \
  bash Scripts/verify-adhoc-candidate-artifact.sh "$ARTIFACT" "$VERSION" "$BUILD" 'invalid'
expect_failure 'missing argument' 'usage:' \
  bash Scripts/verify-adhoc-candidate-artifact.sh "$ARTIFACT" "$VERSION" "$BUILD"

verify >/dev/null
echo 'Ad-hoc candidate artifact metadata and checksum fixtures passed'
