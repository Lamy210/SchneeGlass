# SchneeGlass v0.1 Implementation Plan

## Goal

v0.1 を non-destructive な Folder Glass として成立させる。

## Phase 0 — Bootstrap

### TASK-001 Project Bootstrap

- Xcode project
- macOS 15 deployment target
- Swift 6 language mode
- App Sandbox
- Local `SchneeGlassKit` package
- Target dependency graph
- Architecture CI skeleton

Completion:

```text
Debug build PASS
Release build PASS
unexpected entitlement = 0
```

### TASK-002 Domain Contracts

Implement:

- GlassID
- GlassConfiguration
- GlassPlacement
- FileIdentity
- FolderIdentity
- FileKind
- FolderSnapshot
- GlassContentState
- InteractionState
- DropPlan / DropRejection
- Copy request/result contracts

Completion:

- Domain imports SwiftUI/AppKit = 0
- Domain unit tests PASS

## Phase 1 — Read Path

### TASK-003 Application Ports / Use Cases

Ports:

- FolderSnapshotReading
- FolderAccessControlling
- FileCopying
- ConfigurationPersisting
- FileEventStreaming
- WindowControlling

Use cases:

- CreateGlass
- RemoveGlass
- RestoreApplication
- RefreshGlass
- ExecuteDrop

### TASK-004 Security-Scoped Access

- Bookmark creation/resolve
- stale refresh
- balanced acquire/release
- GlassRuntimeSession lifecycle

### TASK-005 Folder Snapshot Reader

- one-level only
- hidden files default off
- max 500 displayed items
- package before directory classification

### TASK-006 File Event Hub

Order:

```text
scope acquire
→ watcher start
→ initial snapshot
→ dirty reconciliation
→ steady state
```

No polling timer.

## Phase 2 — Window / UI

### TASK-007 Windowing

- NSPanel
- NSHostingView
- Header-only move
- frame persistence
- offscreen recovery
- Current Space default

### TASK-008 Design System / Presentation

States:

```text
loading
ready
empty
unavailable
failed
```

Interaction:

```text
idle
hovered
drop valid
drop invalid
copying
```

- Light/Dark
- Reduce Transparency
- Reduce Motion
- Increase Contrast

## Phase 3 — Safe Copy

### TASK-009 Drop Planner

Pure validation:

- regular file allowed
- same-directory no-op
- folder/package/symlink reject
- collision reject
- unsupported/network/read-only destination reject

### TASK-010 Recovery Metadata

Persist `PendingCopyRecord` before staging mutation.

Unknown `.glass-*` file is never auto-deleted.

### TASK-011 Safe File Copy Engine

```text
batch preflight
→ pending record
→ staging copy
→ basic verify
→ collision recheck
→ internal staging commit
→ metadata cleanup
```

Sequential copy only.

Batch runtime failure:

- previous successes remain
- failed item reported
- later items not attempted
- no rollback deletion

## Phase 4 — Persistence / Recovery

### TASK-012 Configuration Store

- schemaVersion = 1
- atomic write
- max 5 valid backups
- no silent rollback

### TASK-013 Startup Recovery / Safe Mode

Crash-loop prevention:

```text
starting marker
→ restore
→ healthy marker
```

Previous incomplete startup defaults to Safe Mode.

## Phase 5 — Interaction Shell

### TASK-014 Open / Reveal

- Open using actual URL
- Reveal using actual URL
- Display name is never used to construct filesystem path

### TASK-015 Menu Bar / Global Shortcut

- Add Glass
- Show All
- Hide All
- Recovery
- Settings
- Quit

## Phase 6 — Quality / Release

### TASK-016 Static Architecture & Safety Gates

Reject:

- forbidden imports
- mutation APIs outside allowlist
- private CGS
- unapproved `@unchecked Sendable`
- bare TODO/FIXME

### TASK-017 CI

PR:

- Build
- Format/Lint
- Unit
- Architecture
- FileSafety
- Recovery

Main:

- Integration
- Snapshot
- Periphery

Nightly:

- ASan
- TSan
- CodeQL
- Performance

### TASK-018 Release Pipeline

```text
archive
→ sign
→ notarize
→ staple
→ verify entitlements
→ smoke launch
→ publish
```

Unsigned binary must not be presented as trusted stable public release.

## Parallel Groups

After Bootstrap:

```text
Domain
Persistence
Windowing skeleton
Architecture gates
```

After Application ports:

```text
Security scope
Drop planner
Presentation
Open/Reveal
Shortcut/Menu Bar
```

## v0.1 Release Invariants

```text
user source move = 0
user source rename = 0
user source delete = 0
silent overwrite = 0
unknown partial auto-delete = 0
UI -> concrete filesystem adapter dependency = 0
```
