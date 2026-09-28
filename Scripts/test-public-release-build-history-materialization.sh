#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-public-history-materializer-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin" "$FIXTURE/source"

TARGET='0123456789abcdef0123456789abcdef01234567'
SOURCE_BUILD_INFO="$FIXTURE/source/BUILD_INFO.txt"
MANIFEST="$FIXTURE/legacy.tsv"
TAGS="$FIXTURE/tags.txt"

cat > "$SOURCE_BUILD_INFO" <<EOF
version=0.9.0
build=4
source_commit=$TARGET
source_branch=release-v0.9.0
code_signature=adhoc
apple_developer_id_signed=false
apple_notarized=false
distribution=github-adhoc
EOF
DIGEST="$(shasum -a 256 "$SOURCE_BUILD_INFO" | awk '{print $1}')"
printf '# tag\ttarget_commit\tversion\tbuild\tdistribution\tbuild_info_sha256\n' > "$MANIFEST"
printf 'v0.9.0\t%s\t0.9.0\t4\tgithub-adhoc\t%s\n' "$TARGET" "$DIGEST" >> "$MANIFEST"
printf '%s\n' 'v0.9.0' > "$TAGS"

cat > "$FIXTURE/bin/gh" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == 'release' ]] || { echo "unexpected gh command: $*" >&2; exit 90; }
subcommand="${2:-}"
tag="${3:-}"
shift 3

case "$subcommand" in
  view)
    [[ "$tag" == 'v0.9.0' || "$tag" == 'v0.9.1' ]]
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repo|--json)
          shift 2
          ;;
        *)
          echo "unexpected gh release view argument: $1" >&2
          exit 95
          ;;
      esac
    done
    case "${LEGACY_FIXTURE_MODE:?}" in
      legacy)
        printf '{"targetCommitish":"%s","assets":[{"name":"BUILD_INFO.txt"}]}\n' "${LEGACY_FIXTURE_TARGET:?}"
        ;;
      evidence|evidence-missing|evidence-download-failure)
        printf '{"targetCommitish":"%s","assets":[{"name":"RELEASE_EVIDENCE.txt"}]}\n' "${LEGACY_FIXTURE_TARGET:?}"
        ;;
      duplicate-evidence)
        printf '{"targetCommitish":"%s","assets":[{"name":"RELEASE_EVIDENCE.txt"},{"name":"RELEASE_EVIDENCE.txt"}]}\n' "${LEGACY_FIXTURE_TARGET:?}"
        ;;
      malformed-metadata)
        printf '%s\n' '{"targetCommitish":42,"assets":"not-an-array"}'
        ;;
      *)
        echo "unexpected release view fixture mode: ${LEGACY_FIXTURE_MODE:-}" >&2
        exit 96
        ;;
    esac
    ;;
  download)
    dir=''
    pattern=''
    while [[ "$#" -gt 0 ]]; do
      case "$1" in
        --repo)
          shift 2
          ;;
        --pattern)
          pattern="$2"
          shift 2
          ;;
        --dir)
          dir="$2"
          shift 2
          ;;
        *)
          echo "unexpected gh release download argument: $1" >&2
          exit 91
          ;;
      esac
    done
    mkdir -p "$dir"
    case "${LEGACY_FIXTURE_MODE:?}:$pattern" in
      legacy:RELEASE_EVIDENCE.txt)
        exit 1
        ;;
      legacy:BUILD_INFO.txt)
        cp "${LEGACY_FIXTURE_BUILD_INFO:?}" "$dir/BUILD_INFO.txt"
        ;;
      evidence:RELEASE_EVIDENCE.txt)
        cat > "$dir/RELEASE_EVIDENCE.txt" <<'EOF'
schema_version=1
bundle_build=7
EOF
        ;;
      evidence:BUILD_INFO.txt)
        echo 'BUILD_INFO fallback must not run when release evidence exists' >&2
        exit 92
        ;;
      evidence-missing:RELEASE_EVIDENCE.txt)
        exit 0
        ;;
      evidence-download-failure:RELEASE_EVIDENCE.txt)
        exit 42
        ;;
      *)
        echo "unexpected materializer fixture mode/pattern: ${LEGACY_FIXTURE_MODE:-}:$pattern" >&2
        exit 93
        ;;
    esac
    ;;
  *)
    echo "unexpected gh release subcommand: $subcommand" >&2
    exit 94
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/gh"

export LEGACY_FIXTURE_TARGET="$TARGET"
export LEGACY_FIXTURE_BUILD_INFO="$SOURCE_BUILD_INFO"

HISTORY="$FIXTURE/history"
LEGACY_FIXTURE_MODE=legacy PATH="$FIXTURE/bin:$PATH"   bash Scripts/materialize-public-release-build-history.sh     example/SchneeGlass     "$TAGS"     "$HISTORY"     "$MANIFEST"

grep -Fxq 'schema_version=1' "$HISTORY/1/RELEASE_EVIDENCE.txt"
grep -Fxq 'bundle_build=4' "$HISTORY/1/RELEASE_EVIDENCE.txt"
test -f "$HISTORY/1/BUILD_INFO.txt"

rm -rf "$HISTORY"
LEGACY_FIXTURE_MODE=evidence PATH="$FIXTURE/bin:$PATH"   bash Scripts/materialize-public-release-build-history.sh     example/SchneeGlass     "$TAGS"     "$HISTORY"     "$MANIFEST"
grep -Fxq 'bundle_build=7' "$HISTORY/1/RELEASE_EVIDENCE.txt"
test ! -e "$HISTORY/1/BUILD_INFO.txt"

rm -rf "$HISTORY"
set +e
LEGACY_FIXTURE_MODE=evidence-missing PATH="$FIXTURE/bin:$PATH"   bash Scripts/materialize-public-release-build-history.sh     example/SchneeGlass     "$TAGS"     "$HISTORY"     "$MANIFEST"     >"$FIXTURE/evidence-missing.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'declared evidence download success without RELEASE_EVIDENCE.txt' "$FIXTURE/evidence-missing.log"

rm -rf "$HISTORY"
set +e
LEGACY_FIXTURE_MODE=evidence-download-failure PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/materialize-public-release-build-history.sh \
    example/SchneeGlass \
    "$TAGS" \
    "$HISTORY" \
    "$MANIFEST" \
    >"$FIXTURE/evidence-download-failure.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'declares RELEASE_EVIDENCE.txt but it could not be downloaded' "$FIXTURE/evidence-download-failure.log"
test ! -e "$HISTORY/1/BUILD_INFO.txt"

rm -rf "$HISTORY"
set +e
LEGACY_FIXTURE_MODE=duplicate-evidence PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/materialize-public-release-build-history.sh \
    example/SchneeGlass \
    "$TAGS" \
    "$HISTORY" \
    "$MANIFEST" \
    >"$FIXTURE/duplicate-evidence.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'duplicate RELEASE_EVIDENCE.txt assets' "$FIXTURE/duplicate-evidence.log"

rm -rf "$HISTORY"
set +e
LEGACY_FIXTURE_MODE=malformed-metadata PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/materialize-public-release-build-history.sh \
    example/SchneeGlass \
    "$TAGS" \
    "$HISTORY" \
    "$MANIFEST" \
    >"$FIXTURE/malformed-metadata.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'public release metadata is malformed' "$FIXTURE/malformed-metadata.log"

printf '%s\n' 'v0.9.1' > "$TAGS"
rm -rf "$HISTORY"
set +e
LEGACY_FIXTURE_MODE=legacy PATH="$FIXTURE/bin:$PATH"   bash Scripts/materialize-public-release-build-history.sh     example/SchneeGlass     "$TAGS"     "$HISTORY"     "$MANIFEST"     >"$FIXTURE/unknown.log" 2>&1
STATUS=$?
set -e
[[ "$STATUS" -ne 0 ]]
grep -Fq 'legacy release verification failed for v0.9.1' "$FIXTURE/unknown.log"

rm -rf "$FIXTURE"
echo 'Public release build-history materializer fixtures passed'
