#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-release-version-extraction-fixture"
OUTPUT="$FIXTURE/output.log"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"

REAL_SED="$(command -v sed)"
export RELEASE_VERSION_FIXTURE_REAL_SED="$REAL_SED"

cat > "$FIXTURE/bin/xcodebuild" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' \
  'Build settings for action build and target SchneeGlass:' \
  '    MARKETING_VERSION = 0.1.0' \
  '    CURRENT_PROJECT_VERSION = 1'
SHIM
chmod +x "$FIXTURE/bin/xcodebuild"

cat > "$FIXTURE/bin/sed" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${RELEASE_VERSION_FIXTURE_SED_MODE:-normal}" == 'partial-failure' ]]; then
  printf '0.1.0\n'
  exit 42
fi

exec "${RELEASE_VERSION_FIXTURE_REAL_SED:?}" "$@"
SHIM
chmod +x "$FIXTURE/bin/sed"

export PATH="$FIXTURE/bin:$PATH"

# Control: normal extraction resolves the validated release version.
export RELEASE_VERSION_FIXTURE_SED_MODE='normal'
VERSION="$(bash Scripts/resolve-release-version.sh)"
[[ "$VERSION" == '0.1.0' ]]

# Reproduce the former workflow semantics: bash -e without pipefail accepts
# partial plausible output from sed when trailing head succeeds.
export RELEASE_VERSION_FIXTURE_SED_MODE='partial-failure'
set +e
bash -e -c '
  SETTINGS="$(xcodebuild -project SchneeGlass.xcodeproj -scheme SchneeGlass -configuration Release -showBuildSettings)"
  VERSION="$(printf "%s\n" "$SETTINGS" | sed -n "s/^[[:space:]]*MARKETING_VERSION = //p" | head -n 1)"
  test -n "$VERSION"
' >"$OUTPUT" 2>&1
OLD_STATUS=$?
set -e

if [[ "$OLD_STATUS" -ne 0 ]]; then
  cat "$OUTPUT"
  echo 'Fixture failed to reproduce the former release-version false-green behavior.' >&2
  exit 1
fi

# The shared resolver must reject the same partial output + extractor failure.
set +e
bash Scripts/resolve-release-version.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Release version resolver unexpectedly accepted partial output from failed extraction.' >&2
  exit 1
fi

rm -rf "$FIXTURE"
echo 'Release version extraction failure fixture passed'
