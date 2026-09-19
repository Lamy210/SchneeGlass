#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-swift-format-enumeration-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
OUTPUT="$FIXTURE/changed-swift.bin"
LOG="$FIXTURE/output.log"

cat > "$FIXTURE/bin/git" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == 'diff' ]]; then
  echo 'fixture: changed-Swift enumeration unavailable' >&2
  exit 42
fi

echo "unexpected git command in changed-Swift fixture: $*" >&2
exit 90
SHIM
chmod +x "$FIXTURE/bin/git"

set +e
PATH="$FIXTURE/bin:$PATH" \
  bash Scripts/collect-changed-swift-files.sh \
    0123456789abcdef0123456789abcdef01234567 \
    "$OUTPUT" \
  >"$LOG" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$LOG"
  echo 'Changed-Swift enumeration unexpectedly succeeded after git diff failed.' >&2
  exit 1
fi

grep -Fq 'Swift-format changed-file enumeration failed:' "$LOG"

rm -rf "$FIXTURE"
echo 'Swift-format changed-file enumeration failure fixture passed'
