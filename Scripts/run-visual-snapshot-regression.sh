#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <log-file>" >&2
  exit 2
fi

log="$1"
: > "$log"

run_suite() {
  local suite="$1"
  local statuses=()

  set +e
  swift test \
    --package-path Packages/SchneeGlassKit \
    --filter "$suite" \
    2>&1 | tee -a "$log"
  statuses=("${PIPESTATUS[@]}")
  set -e

  if [[ "${statuses[0]}" -ne 0 ]]; then
    echo "Visual snapshot suite failed: $suite (swift status ${statuses[0]})" >&2
    return 1
  fi

  if [[ "${statuses[1]}" -ne 0 ]]; then
    echo "Visual snapshot log capture failed: $suite (tee status ${statuses[1]})" >&2
    return 1
  fi
}

run_suite DesktopGlassVisualSnapshotTests
run_suite DesignSystemComponentVisualSnapshotTests
run_suite WorkspaceVisualSnapshotTests

bash Scripts/verify-visual-snapshots.sh DesktopGlassVisualSnapshotTests "$log"
bash Scripts/verify-visual-snapshots.sh DesignSystemComponentVisualSnapshotTests "$log"
bash Scripts/verify-visual-snapshots.sh WorkspaceVisualSnapshotTests "$log"
