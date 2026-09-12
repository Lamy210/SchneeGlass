#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_path="$repo_root/Packages/SchneeGlassKit"
snapshot_path="$package_path/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__"
canonical_xcode="/Applications/Xcode_26.6.app/Contents/Developer"

if [[ -d "$canonical_xcode" ]]; then
  export DEVELOPER_DIR="$canonical_xcode"
fi

actual_xcode="$(xcodebuild -version | head -n 1)"
if [[ "$actual_xcode" != "Xcode 26.6" ]]; then
  printf 'Visual snapshots must be recorded with Xcode 26.6; found: %s\n' "$actual_xcode" >&2
  exit 1
fi

export SCHNEEGLASS_VISUAL_SNAPSHOTS=1
export SNAPSHOT_TESTING_RECORD=all

snapshot_suites=(
  DesktopGlassVisualSnapshotTests
  DesignSystemComponentVisualSnapshotTests
  WorkspaceVisualSnapshotTests
)

printf 'Recording SchneeGlass visual snapshots with %s...\n' "$actual_xcode"
for suite in "${snapshot_suites[@]}"; do
  printf 'Recording %s...\n' "$suite"
  set +e
  swift test \
    --package-path "$package_path" \
    --filter "$suite"
  record_status=$?
  set -e

  # SnapshotTesting intentionally reports failures while record mode is enabled.
  if [[ ! -d "$snapshot_path" ]]; then
    printf 'Snapshot recording did not create %s for %s (swift test exit %d).\n' \
      "$snapshot_path" "$suite" "$record_status" >&2
    exit 1
  fi
done

printf 'Verifying freshly recorded snapshots...\n'
export SNAPSHOT_TESTING_RECORD=never
for suite in "${snapshot_suites[@]}"; do
  swift test \
    --package-path "$package_path" \
    --filter "$suite"
done

printf 'Visual snapshots updated successfully. Review the PNG diff before committing.\n'
