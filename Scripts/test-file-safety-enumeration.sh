#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-file-safety-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
OUTPUT="$FIXTURE/output.log"

REAL_GREP="$(command -v grep)"

cat > "$FIXTURE/bin/grep" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
echo 'fixture: grep enumeration unavailable' >&2
exit 42
SHIM
chmod +x "$FIXTURE/bin/grep"

set +e
PATH="$FIXTURE/bin:$PATH" bash Scripts/verify-file-safety.sh >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'File Safety Guard unexpectedly passed when mutation enumeration failed.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'File safety verification failed: unable to enumerate filesystem mutation pattern' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'File Safety Guard enumeration failure fixture passed'
