# SchneeGlass Testing Strategy

## 1. 方針

Test coverage percentage より、壊してはいけない Invariant を優先します。

Release-critical invariants:

1. Copy failure で source が変更されない
2. Existing destination を暗黙 overwrite しない
3. v0.1 で user-owned Move/Delete/Rename/Replace をしない
4. Unknown partial を自動削除しない
5. Permission failure を Empty と表示しない
6. Config corruption から Recovery 可能
7. UI が filesystem mutation adapter に直接依存しない

## 2. Test Categories

```text
Unit
Architecture
FileSafety
Recovery
Integration
Snapshot
UI
Performance
ReleaseArtifact
```

優先順位:

```text
FileSafety
> Recovery
> Architecture
> Domain
> Integration
> UI
```

## 3. Libraries / Tools

- Swift Testing
- XCTest / XCUITest
- SnapshotTesting (test-only)
- swift-clocks (test-only)
- swift-format
- SwiftLint
- Periphery
- CodeQL
- Address Sanitizer
- Thread Sanitizer
- Main Thread Checker

Runtime binary に test-only dependency を持ち込みません。

## 4. Test Plans

### Fast — every PR

- Build
- Format
- Lint
- Domain Unit
- Application Unit
- Architecture rules

### Safety — every PR

- FileSafety
- Recovery
- Configuration
- Fault injection

### Integration — main

- Security-scoped access
- FSEvents
- File coordination
- Window/AppKit integration

### Diagnostics — nightly/release

- ASan
- TSan
- Main Thread Checker
- Periphery
- CodeQL

### Release

- Critical suites
- Release build
- codesign verification
- entitlement verification
- notarization verification
- smoke launch

## 5. Filesystem Test Isolation

実ユーザーフォルダを Test に使用しません。

各 Test は独自 root を持ちます。

```text
/tmp/SchneeGlassTests/<UUID>/
├ source/
├ destination/
└ unrelated/
```

## 6. Fault Injection

`FaultInjectingFileSystem` test adapter で最低限次を再現します。

```text
permissionDenied
sourceMissing
destinationMissing
diskFull(afterBytes:)
commitCollision
cancelled
unexpectedIO
```

Fake adapter のみで完結せず、Foundation/FileManager を使った real filesystem integration test も実施します。

## 7. Critical Scenarios

### Copy

- Regular file success
- Collision preflight
- Same-directory no-op
- Folder/package/symlink rejection
- Multi-file success
- Batch deterministic rejection → 0 copied
- Runtime failure mid-batch → previous success retained, remaining not attempted
- Disk full
- Source disappears
- Destination disappears
- Commit collision race

### Recovery

- Recovery metadata + partial
- Recovery metadata + final
- Unknown `.glass-*` file
- Config corruption
- All backups corrupt
- Backup rotation
- Startup crash marker
- Safe Mode

### Security Scope

- Acquire / release balance
- Duplicate release
- Stale bookmark refresh
- Bookmark resolution failure

### FSEvents

- Initial snapshot race
- Event burst
- dropped events / root change
- Final filesystem state equality (event count は assert しない)

### UI / Accessibility

- Light / Dark
- Reduce Transparency
- Reduce Motion
- Long filename
- Empty / unavailable / failure

## 8. Architecture Tests

CI は最低限以下を reject します。

```text
SchneeGlassDomain imports SwiftUI/AppKit
FileDomain imports SwiftUI
SchneeGlassPresentation imports concrete filesystem/persistence adapter
Private CGS symbols
Filesystem mutation APIs outside allowlist
Bare TODO/FIXME
Unapproved @unchecked Sendable
```

## 9. Coverage

Coverage は補助指標です。

推奨目標:

- Domain / DropPlanner: 90–95%+
- Recovery: 90%+
- FileOperations: 85%+
- Presentation: 80% 前後
- UI rendering: percentage gate なし

Critical path は coverage 率ではなく scenario completeness で release 判定します。
