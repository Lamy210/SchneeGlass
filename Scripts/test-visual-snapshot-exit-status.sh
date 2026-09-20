#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

FIXTURE="${RUNNER_TEMP:-/tmp}/schneeglass-visual-snapshot-exit-fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/bin"
LOG="$FIXTURE/visual-snapshots.log"
OUTPUT="$FIXTURE/output.log"
REAL_GREP="$(command -v grep)"

cat > "$FIXTURE/bin/swift" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail

FILTER=''
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --filter)
      FILTER="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "$FILTER" in
  DesktopGlassVisualSnapshotTests)
    MARKER='SCHNEEGLASS_VISUAL_SNAPSHOT_RESULT'
    ;;
  DesignSystemComponentVisualSnapshotTests)
    MARKER='SCHNEEGLASS_DESIGN_SYSTEM_SNAPSHOT_RESULT'
    ;;
  WorkspaceVisualSnapshotTests)
    MARKER='SCHNEEGLASS_WORKSPACE_SNAPSHOT_RESULT'
    ;;
  *)
    echo "fixture: unexpected swift filter: $FILTER" >&2
    exit 91
    ;;
esac

awk -v prefix="$FILTER." -v marker="$MARKER" '
  index($0, prefix) == 1 {
    print marker " " substr($0, length(prefix) + 1)
  }
' Scripts/visual-snapshot-contract.txt

if [[ "$FILTER" == 'DesktopGlassVisualSnapshotTests' ]]; then
  echo 'fixture: Desktop visual snapshot suite failed after emitting complete markers' >&2
  exit 42
fi
SHIM
chmod +x "$FIXTURE/bin/swift"

set +e
PATH="$FIXTURE/bin:$PATH" bash Scripts/run-visual-snapshot-regression.sh "$LOG" >"$OUTPUT" 2>&1
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUTPUT"
  echo 'Visual snapshot runner unexpectedly accepted a failing suite after complete marker emission.' >&2
  exit 1
fi

"$REAL_GREP" -Fq \
  'Visual snapshot suite failed: DesktopGlassVisualSnapshotTests' \
  "$OUTPUT"

rm -rf "$FIXTURE"
echo 'Visual snapshot process-exit fixture passed'
