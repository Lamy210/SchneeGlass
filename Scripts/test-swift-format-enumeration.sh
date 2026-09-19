#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-swift-format-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

cat > "$FIXTURE/bin/git" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

[[ "${1:-}" == 'diff' ]] || {
  echo "unexpected git command in changed-Swift fixture: $*" >&2
  exit 90
}

case "${SWIFT_DIFF_FIXTURE_MODE:?}" in
  failure)
    printf 'App/Partial.swift\0'
    echo 'fixture: changed-Swift enumeration unavailable' >&2
    exit 42
    ;;
  empty)
    exit 0
    ;;
  files)
    printf 'App/Foo.swift\0'
    printf 'Packages/SchneeGlassKit/Sources/Example Dir/Bar.swift\0'
    exit 0
    ;;
  *)
    echo "unexpected Swift diff fixture mode: ${SWIFT_DIFF_FIXTURE_MODE:-}" >&2
    exit 91
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/git"

BASE_SHA='0123456789abcdef0123456789abcdef01234567'

# A partial diff followed by an enumeration error must not yield a trusted output file.
FAIL_OUTPUT="$FIXTURE/failure.bin"
FAIL_LOG="$FIXTURE/failure.log"
set +e
SWIFT_DIFF_FIXTURE_MODE='failure' \
  PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/collect-changed-swift-files.sh "$BASE_SHA" "$FAIL_OUTPUT" \
  >"$FAIL_LOG" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$FAIL_LOG"
  echo 'Changed-Swift enumeration unexpectedly succeeded after git diff failed.' >&2
  exit 1
fi
grep -Fq \
  'Swift-format changed-file enumeration failed: git diff could not enumerate changed Swift files (status 42)' \
  "$FAIL_LOG"
if [[ -e "$FAIL_OUTPUT" ]]; then
  echo 'Failed changed-Swift enumeration left a trusted output file behind.' >&2
  exit 1
fi

# A successful zero-match diff remains a valid empty result.
EMPTY_OUTPUT="$FIXTURE/empty.bin"
SWIFT_DIFF_FIXTURE_MODE='empty' \
  PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/collect-changed-swift-files.sh "$BASE_SHA" "$EMPTY_OUTPUT"
[[ -f "$EMPTY_OUTPUT" && ! -s "$EMPTY_OUTPUT" ]] || {
  echo 'Zero-match changed-Swift enumeration did not produce an empty output file.' >&2
  exit 1
}

# Successful enumeration preserves NUL-delimited paths, including whitespace.
FILES_OUTPUT="$FIXTURE/files.bin"
SWIFT_DIFF_FIXTURE_MODE='files' \
  PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/collect-changed-swift-files.sh "$BASE_SHA" "$FILES_OUTPUT"

FILES=()
while IFS= read -r -d '' file; do
  FILES+=("$file")
done < "$FILES_OUTPUT"

[[ "${#FILES[@]}" -eq 2 ]] || {
  echo "Expected 2 changed Swift paths, got ${#FILES[@]}." >&2
  exit 1
}
[[ "${FILES[0]}" == 'App/Foo.swift' ]] || {
  echo "Unexpected first changed Swift path: ${FILES[0]}" >&2
  exit 1
}
[[ "${FILES[1]}" == 'Packages/SchneeGlassKit/Sources/Example Dir/Bar.swift' ]] || {
  echo "Unexpected second changed Swift path: ${FILES[1]}" >&2
  exit 1
}

rm -rf "$FIXTURE"
echo 'Swift-format changed-file enumeration fixtures passed'
