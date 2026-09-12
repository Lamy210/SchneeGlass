# SchneeGlass UI Gallery

This gallery shows the canonical visual regression references for the current SchneeGlass UI.

The images are **not copied into a separate documentation asset directory**. Every image below points directly to the committed snapshot baseline under `Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__`, so the visual regression reference remains the single image source of truth.

## Visual contract

- Canonical renderer: GitHub-hosted macOS 26 / Xcode 26.6
- Contract manifest: [`Scripts/visual-snapshot-contract.txt`](../Scripts/visual-snapshot-contract.txt)
- Verification: [`Scripts/verify-visual-snapshots.sh`](../Scripts/verify-visual-snapshots.sh)
- Explicit local refresh: `bash Scripts/update-visual-snapshots.sh`
- CI verifies snapshots in record-never mode; CI never accepts or records a new baseline automatically.

These are deterministic synthetic fixtures for review and regression detection, not screenshots of user data. An intentional visual change should update the affected snapshot references in a dedicated reviewable change; this gallery then updates automatically because it references those same files.

## Workspace

### Populated workspace

| Light | Dark |
| --- | --- |
| ![Populated workspace in light appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/WorkspaceVisualSnapshotTests/populatedLight.macos-26-xcode-26-6.png) | ![Populated workspace in dark appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/WorkspaceVisualSnapshotTests/populatedDark.macos-26-xcode-26-6.png) |

### Empty and message states

| Empty | Empty with message |
| --- | --- |
| ![Empty workspace](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/WorkspaceVisualSnapshotTests/emptyLight.macos-26-xcode-26-6.png) | ![Empty workspace with message banner](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/WorkspaceVisualSnapshotTests/emptyWithMessageLight.macos-26-xcode-26-6.png) |

### Populated workspace with message

![Populated workspace with message banner](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/WorkspaceVisualSnapshotTests/populatedWithMessageLight.macos-26-xcode-26-6.png)

## Desktop Glass

### Ready and empty

| Ready / Light | Ready / Dark |
| --- | --- |
| ![Ready desktop Glass in light appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/readyLight.macos-26-xcode-26-6.png) | ![Ready desktop Glass in dark appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/readyDark.macos-26-xcode-26-6.png) |

| Empty / Light | Empty / Dark |
| --- | --- |
| ![Empty desktop Glass in light appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/emptyLight.macos-26-xcode-26-6.png) | ![Empty desktop Glass in dark appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/emptyDark.macos-26-xcode-26-6.png) |

### Availability and failure

| Unavailable | Failed |
| --- | --- |
| ![Unavailable desktop Glass](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/unavailableLight.macos-26-xcode-26-6.png) | ![Failed desktop Glass](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/failedLight.macos-26-xcode-26-6.png) |

### Drag and drop validation

| Accepted drop | Rejected drop |
| --- | --- |
| ![Accepted drag and drop overlay](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/dropValidLight.macos-26-xcode-26-6.png) | ![Rejected drag and drop overlay](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesktopGlassVisualSnapshotTests/dropInvalidLight.macos-26-xcode-26-6.png) |

## Design System components

### State message

| Detail / Light | No detail / Dark |
| --- | --- |
| ![State message with detail in light appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesignSystemComponentVisualSnapshotTests/stateMessageDetailLight.macos-26-xcode-26-6.png) | ![State message without detail in dark appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesignSystemComponentVisualSnapshotTests/stateMessageNoDetailDark.macos-26-xcode-26-6.png) |

### File tile

| Regular file / Light | Directory / Light |
| --- | --- |
| ![Regular-file tile in light appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesignSystemComponentVisualSnapshotTests/fileTileRegularLight.macos-26-xcode-26-6.png) | ![Directory tile in light appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesignSystemComponentVisualSnapshotTests/fileTileDirectoryLight.macos-26-xcode-26-6.png) |

| Package / Dark | Long filename / Light |
| --- | --- |
| ![Package tile in dark appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesignSystemComponentVisualSnapshotTests/fileTilePackageDark.macos-26-xcode-26-6.png) | ![Long two-line filename tile in light appearance](../Packages/SchneeGlassKit/Tests/SchneeGlassVisualSnapshotTests/__Snapshots__/DesignSystemComponentVisualSnapshotTests/fileTileLongNameLight.macos-26-xcode-26-6.png) |

## Coverage boundary

This gallery mirrors the canonical visual contract rather than attempting to document every possible runtime combination. Animated indeterminate states such as loading/copying are intentionally not treated as image baselines while they remain nondeterministic. Behavioral, safety, accessibility, and recovery semantics continue to be covered by the normal test suites and manual QA documentation.

See [`TESTING.md`](../TESTING.md) for the complete verification policy and [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md) for the visual architecture and component rules.
