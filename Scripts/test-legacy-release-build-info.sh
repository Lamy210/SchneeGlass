#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-legacy-build-info-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE"

TARGET='0123456789abcdef0123456789abcdef01234567'
BUILD_INFO="$FIXTURE/BUILD_INFO.txt"
MANIFEST="$FIXTURE/legacy.tsv"

write_valid_build_info() {
  cat > "$BUILD_INFO" <<EOF
version=0.9.0
build=4
source_commit=$TARGET
source_branch=release-v0.9.0
code_signature=adhoc
apple_developer_id_signed=false
apple_notarized=false
distribution=github-adhoc
EOF
}

write_manifest() {
  local digest
  digest="$(shasum -a 256 "$BUILD_INFO" | awk '{print $1}')"
  printf '# tag\ttarget_commit\tversion\tbuild\tdistribution\tbuild_info_sha256\n' > "$MANIFEST"
  printf 'v0.9.0\t%s\t0.9.0\t4\tgithub-adhoc\t%s\n' "$TARGET" "$digest" >> "$MANIFEST"
}

write_valid_build_info
write_manifest

BUILD="$(bash Scripts/verify-legacy-release-build-info.sh "$MANIFEST" v0.9.0 "$TARGET" "$BUILD_INFO")"
[[ "$BUILD" == '4' ]]

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$FIXTURE/failure.log" 2>&1; then
    cat "$FIXTURE/failure.log"
    echo "Legacy build-info verifier unexpectedly accepted: $label" >&2
    exit 1
  fi
}

printf '\ntampered=true\n' >> "$BUILD_INFO"
expect_failure   'BUILD_INFO digest mismatch'   bash Scripts/verify-legacy-release-build-info.sh "$MANIFEST" v0.9.0 "$TARGET" "$BUILD_INFO"
grep -Fq 'BUILD_INFO digest mismatch' "$FIXTURE/failure.log"

write_valid_build_info
write_manifest
expect_failure   'release target mismatch'   bash Scripts/verify-legacy-release-build-info.sh     "$MANIFEST"     v0.9.0     fedcba9876543210fedcba9876543210fedcba98     "$BUILD_INFO"
grep -Fq 'release target mismatch' "$FIXTURE/failure.log"

cp "$MANIFEST" "$FIXTURE/legacy-row-copy.tsv"
tail -n +2 "$FIXTURE/legacy-row-copy.tsv" >> "$MANIFEST"
expect_failure   'duplicate manifest tag'   bash Scripts/verify-legacy-release-build-info.sh "$MANIFEST" v0.9.0 "$TARGET" "$BUILD_INFO"
grep -Fq 'release tag is not exactly once in legacy manifest' "$FIXTURE/failure.log"

write_manifest
expect_failure   'unknown legacy tag'   bash Scripts/verify-legacy-release-build-info.sh "$MANIFEST" v0.9.1 "$TARGET" "$BUILD_INFO"
grep -Fq 'release tag is not exactly once in legacy manifest' "$FIXTURE/failure.log"

rm -rf "$FIXTURE"
echo 'Legacy release BUILD_INFO fixtures passed'
