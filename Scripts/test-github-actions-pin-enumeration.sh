#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-action-pin-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
OUTPUT="$FIXTURE/output.log"

REAL_GREP="$(command -v grep)"

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' '.github/workflows/bootstrap-ci.yml:1:        uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1'
echo 'fixture: workflow action enumeration unavailable after partial output' >&2
exit 42
SHIM
chmod +x "$FIXTURE/bin/grep"

set +e
PATH="$FIXTURE/bin:$PATH" bash Scripts/verify-github-actions-pins.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'GitHub Actions pin guard unexpectedly accepted partial enumeration after grep failure.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'GitHub Actions pin verification failed: unable to enumerate workflow action references' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'GitHub Actions pin enumeration failure fixture passed'
