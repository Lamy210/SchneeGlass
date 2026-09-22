#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-fixture-base64"
OUTPUT="$FIXTURE/output.log"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
printf 'A' > "$FIXTURE/input.bin"

cat > "$FIXTURE/bin/base64" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

case "${RELEASE_FIXTURE_BASE64_MODE:-normal}" in
  normal)
    exec /usr/bin/base64 "$@"
    ;;
  partial-failure)
    printf 'QQ=='
    exit 42
    ;;
  *)
    echo "unexpected fixture Base64 mode: ${RELEASE_FIXTURE_BASE64_MODE:-}" >&2
    exit 91
    ;;
esac
SHIM
chmod +x "$FIXTURE/bin/base64"
export SCHNEEGLASS_FIXTURE_BASE64_BIN="$FIXTURE/bin/base64"

export RELEASE_FIXTURE_BASE64_MODE='normal'
ENCODED="$(bash Scripts/encode-release-fixture-base64.sh "$FIXTURE/input.bin")"
[[ "$ENCODED" == 'QQ==' ]]

# Reproduce the former fixture semantics. Even with pipefail enabled in the
# subshell, export reports its own success and masks the failed substitution.
export RELEASE_FIXTURE_BASE64_MODE='partial-failure'
set +e
bash -e -o pipefail -c '
  export VALUE="$("$SCHNEEGLASS_FIXTURE_BASE64_BIN" < "$1" | tr -d "\n")"
  [[ "$VALUE" == "QQ==" ]]
' _ "$FIXTURE/input.bin" >"$OUTPUT" 2>&1
OLD_STATUS=$?
set -e

if [[ "$OLD_STATUS" -ne 0 ]]; then
  cat "$OUTPUT"
  echo 'Fixture failed to reproduce export masking a failed Base64 substitution.' >&2
  exit 1
fi

set +e
bash Scripts/encode-release-fixture-base64.sh "$FIXTURE/input.bin" >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Safe fixture Base64 encoder unexpectedly accepted partial output from a failed producer.' >&2
  exit 1
fi

grep -Fq 'Release fixture Base64 encoding failed: Base64 encoder pipeline exited with status 42' "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Release fixture Base64 encoding failure fixture passed'
