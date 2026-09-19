#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-architecture-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
OUTPUT="$FIXTURE/output.log"

REAL_GREP="$(command -v grep)"

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

ARGS="$*"
if [[ "$ARGS" == *'TODO|FIXME'* ]]; then
  exit 1
fi

printf '%s\n' \
  '/tmp/SchneeGlassFixture/Packages/SchneeGlassKit/Sources/SchneeGlassDomain/Forbidden.swift:1:import AppKit'
echo 'fixture: architecture enumeration unavailable after partial output' >&2
exit 42
SHIM
chmod +x "$FIXTURE/bin/grep"

set +e
PATH="$FIXTURE/bin:$PATH" bash Scripts/verify-architecture.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Architecture Guard unexpectedly accepted partial enumeration after grep failure.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'Architecture verification failed: unable to enumerate' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Architecture Guard enumeration failure fixture passed'
