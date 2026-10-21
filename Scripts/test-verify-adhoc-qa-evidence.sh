#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
ARTIFACT="$TMP/artifact"
mkdir -p "$ARTIFACT"

VERSION='0.2.0'
BUILD='3'
SHA='0123456789abcdef0123456789abcdef01234567'
RUN_ID='123456789'
REVIEWER='trusted-reviewer'
ZIP="SchneeGlass-$VERSION-adhoc-candidate.zip"
printf 'synthetic archive, not a signed Mac application\n' > "$ARTIFACT/$ZIP"
for file in README.txt CODESIGN_DETAILS.txt ENTITLEMENTS.plist; do
  printf 'fixture payload\n' > "$ARTIFACT/$file"
done
(cd "$ARTIFACT" && shasum -a 256 "$ZIP" > SHA256SUMS)
DIGEST="$(shasum -a 256 "$ARTIFACT/$ZIP" | awk '{print $1}')"
cat > "$ARTIFACT/BUILD_INFO.txt" <<EOF
version=$VERSION
build=$BUILD
source_commit=$SHA
source_branch=main
code_signature=adhoc
apple_developer_id_signed=false
apple_notarized=false
minimum_macos=15.0
executable_info=synthetic-fixture
distribution=github-adhoc-candidate
EOF

EVIDENCE="$TMP/QA_EVIDENCE.txt"
cat > "$EVIDENCE" <<EOF
schema_version=1
candidate_run_id=$RUN_ID
candidate_run_attempt=1
candidate_source_commit=$SHA
candidate_version=$VERSION
candidate_build=$BUILD
candidate_archive_sha256=$DIGEST
qa_result=pass
reviewed_by=$REVIEWER
reviewed_at=2026-10-22T06:00:00Z
EOF
cp "$EVIDENCE" "$TMP/good"

verify() {
  bash Scripts/verify-adhoc-qa-evidence.sh \
    "$ARTIFACT" "$EVIDENCE" "$VERSION" "$BUILD" "$SHA" "$RUN_ID" "$REVIEWER"
}

reject() {
  local name="$1" message="$2"
  shift 2
  local output
  if output="$("$@" 2>&1)"; then
    echo "Accepted invalid QA fixture: $name" >&2
    exit 1
  fi
  if [[ "$output" != *"$message"* ]]; then
    echo "Unexpected error for $name: $output" >&2
    exit 1
  fi
}

verify >/dev/null
# Field order is not semantically significant.
LC_ALL=C sort "$TMP/good" > "$EVIDENCE"
verify >/dev/null
cp "$TMP/good" "$EVIDENCE"

while IFS='|' read -r before after diagnostic; do
  sed "s/$before/$after/" "$TMP/good" > "$EVIDENCE"
  reject "$after" "$diagnostic" verify
  cp "$TMP/good" "$EVIDENCE"
done <<EOF
schema_version=1|schema_version=2|unsupported QA schema
candidate_run_id=$RUN_ID|candidate_run_id=111|QA candidate run id mismatch
candidate_run_attempt=1|candidate_run_attempt=2|QA must bind first run attempt
candidate_source_commit=$SHA|candidate_source_commit=89abcdef0123456789abcdef0123456789abcdef|QA source commit mismatch
candidate_version=$VERSION|candidate_version=0.2.1|QA candidate version mismatch
candidate_build=$BUILD|candidate_build=4|QA candidate build mismatch
candidate_archive_sha256=$DIGEST|candidate_archive_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa|QA archive digest mismatch
qa_result=pass|qa_result=fail|QA result must be pass
reviewed_by=$REVIEWER|reviewed_by=impostor|QA reviewer mismatch
reviewed_at=2026-10-22T06:00:00Z|reviewed_at=yesterday|QA reviewed_at must be UTC ISO-8601 seconds
EOF

printf 'qa_result=pass\n' >> "$EVIDENCE"
reject 'duplicate approval' 'duplicate QA evidence field: qa_result' verify
cp "$TMP/good" "$EVIDENCE"

printf 'unexpected=yes\n' >> "$EVIDENCE"
reject 'unknown field' 'unknown QA evidence field: unexpected' verify
cp "$TMP/good" "$EVIDENCE"

printf 'malformed-line\n' >> "$EVIDENCE"
reject 'malformed line' 'malformed QA evidence line' verify
cp "$TMP/good" "$EVIDENCE"

sed '/^candidate_run_id=/d' "$TMP/good" > "$EVIDENCE"
reject 'missing field' 'QA evidence must have exactly 10 fields' verify
cp "$TMP/good" "$EVIDENCE"

sed 's/qa_result=pass/qa_result=/' "$TMP/good" > "$EVIDENCE"
reject 'empty field' 'empty QA evidence field: qa_result' verify
cp "$TMP/good" "$EVIDENCE"

printf 'tampered archive\n' >> "$ARTIFACT/$ZIP"
reject 'modified archive' 'candidate artifact validation failed' verify
printf 'synthetic archive, not a signed Mac application\n' > "$ARTIFACT/$ZIP"

mv "$EVIDENCE" "$TMP/evidence-actual"
ln -s "$TMP/evidence-actual" "$EVIDENCE"
reject 'symlink QA record' 'QA evidence must be a nonempty regular file, not a symlink' verify
rm "$EVIDENCE"
mv "$TMP/evidence-actual" "$EVIDENCE"

reject 'untrusted caller run id' 'expected run id must be a positive decimal' \
  bash Scripts/verify-adhoc-qa-evidence.sh "$ARTIFACT" "$EVIDENCE" "$VERSION" "$BUILD" "$SHA" '0' "$REVIEWER"
reject 'malformed reviewer' 'expected reviewer must be a GitHub login' \
  bash Scripts/verify-adhoc-qa-evidence.sh "$ARTIFACT" "$EVIDENCE" "$VERSION" "$BUILD" "$SHA" "$RUN_ID" 'invalid reviewer'
reject 'missing caller argument' 'usage:' \
  bash Scripts/verify-adhoc-qa-evidence.sh "$ARTIFACT" "$EVIDENCE" "$VERSION" "$BUILD" "$SHA" "$RUN_ID"

verify >/dev/null
echo 'Ad-hoc QA digest-binding positive and negative fixtures passed'
