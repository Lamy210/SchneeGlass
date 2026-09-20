#!/usr/bin/env bash
set -e

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <log-file>" >&2
  exit 2
fi

log="$1"

{
  swift test \
    --package-path Packages/SchneeGlassKit \
    --filter DesktopGlassVisualSnapshotTests
  swift test \
    --package-path Packages/SchneeGlassKit \
    --filter DesignSystemComponentVisualSnapshotTests
  swift test \
    --package-path Packages/SchneeGlassKit \
    --filter WorkspaceVisualSnapshotTests
} 2>&1 | tee "$log"

bash Scripts/verify-visual-snapshots.sh DesktopGlassVisualSnapshotTests "$log"
bash Scripts/verify-visual-snapshots.sh DesignSystemComponentVisualSnapshotTests "$log"
bash Scripts/verify-visual-snapshots.sh WorkspaceVisualSnapshotTests "$log"
