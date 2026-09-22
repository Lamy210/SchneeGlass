#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-xcode-version-probe-fixture"
OUTPUT="$FIXTURE/output.log"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

cat > "$FIXTURE/bin/xcodebuild" <<'SHIM'
#!/usr/bin/env bash
printf 'Xcode 26.6\nBuild version 17G29\n'
exit 42
SHIM
chmod +x "$FIXTURE/bin/xcodebuild"

export PATH="$FIXTURE/bin:$PATH"

# Reproduce the current workflow semantics: bash -e without pipefail accepts
# partial expected output from xcodebuild when the trailing grep succeeds.
set +e
bash -e -c "xcodebuild -version | grep -F 'Xcode 26.6' >/dev/null"
OLD_STATUS=$?
set -e

if [[ "$OLD_STATUS" -ne 0 ]]; then
  echo "Fixture failed to reproduce the existing toolchain false-green behavior." >&2
  exit 1
fi

set +e
bash Scripts/verify-xcode-version.sh 'Xcode 26.6' >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo "Xcode version verifier unexpectedly accepted partial expected output from failed enumeration." >&2
  exit 1
fi

grep -Fq   'Xcode version verification failed: xcodebuild -version exited with status 42'   "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Xcode version probe failure fixture passed'
