# SchneeGlass Testing Strategy

SchneeGlass はファイルを扱うため、テストを「実装後の確認」ではなく Architecture の一部として扱います。

## 1. 最優先Invariant

```text
Source file loss = 0
Silent overwrite = 0
User-owned Move/Rename/Delete = 0
Unknown partial auto-delete = 0
Security scope leak = 0
UI -> concrete filesystem mutation adapter = 0
```

Coverage率だけではRelease可否を決めません。

Critical scenario coverageを優先します。

---

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

Priority:

```text
FileSafety
>
Recovery
>
Architecture
>
Domain
>
Integration
>
UI
```

---

## 3. Bootstrap Test

現在のBootstrapでは `Packages/SchneeGlassKit` に対してSwift Testingを使用します。

初期Test対象:

- `GlassConfiguration` title invariant
- `GlassPlacement` minimum size invariant
- Codable decode経由でもInvariantが維持されること
- `FileKind` contract
- `FileIdentity` URL normalization
- Batch Copyのpartial-success result contract

実行:

```bash
swift test --package-path Packages/SchneeGlassKit
```

---

## 4. CI Safety Guards

Bootstrap CIでは次を必須とします。

```text
Scripts/verify-public-repo.sh
Scripts/verify-architecture.sh
Scripts/verify-file-safety.sh
swift test --package-path Packages/SchneeGlassKit
```

### Public Repository Guard

検出対象:

- credential-like tracked file
- private-key marker
- high-confidence GitHub token pattern

これはGitHub Secret Scanning等を置き換えるものではなく、Repository内の第一防衛線です。

### Architecture Guard

検出対象:

- Domain → SwiftUI/AppKit/CoreServices/GRDB import
- Presentation → FileSystem/Persistence Concrete Adapter import
- Private CGS symbol
- 無承認`@unchecked Sendable`
- Swift source内のIssue番号なしTODO/FIXME

### File Safety Guard

`removeItem` / `moveItem` / `replaceItem` 相当APIの利用場所を検査します。

v0.1で許可予定のinternal moveは、Glass-owned staging fileのfinal commitに限定し、`InternalStagingCommitter.swift` だけをallowlistにします。

---

## 5. FileSafety Tests — 実装フェーズ

実Filesystem用Test root:

```text
/tmp/SchneeGlassTests/<UUID>/
├ source/
├ destination/
└ unrelated/
```

各Testは独立したUUID rootを使用します。

実ユーザーFolderや会社FolderをFixtureに使用してはいけません。

主要Case:

- normal regular-file copy
- collision
- same-directory no-op
- folder/package/symlink reject
- multi-file preflight failure
- disk full fault injection
- source disappears
- destination disappears
- commit collision race
- partial recovery
- unknown `.glass-*` safety

---

## 6. Fault Injection

Test Adapterとして `FaultInjectingFileSystem` を導入予定です。

Fault:

```text
permissionDenied
sourceMissing
destinationMissing
diskFull(afterBytes:)
commitCollision
cancelled
unexpectedIO
```

Fakeのみでは不十分です。

Foundation/FileManager/NSFileCoordinatorを使用したIntegration Testも実施します。

---

## 7. Recovery Tests

対象:

```text
config corruption
backup rotation
all backups corrupt
stale bookmark
bookmark failure
duplicate security-scope release
startup crash marker
safe mode
offscreen window
pending copy metadata
ambiguous partial
```

Recovery testではUser fileを自動削除しないことも確認します。

---

## 8. FSEvents Tests

Event件数をassertしません。

検証対象は最終observable stateです。

```text
Filesystem change
↓
eventually
↓
FolderSnapshot == final filesystem state
```

Startup snapshot中のeventを取りこぼさないTestも必須です。

---

## 9. Test-only Dependencies

予定:

```text
SnapshotTesting
swift-clocks
```

Runtime BinaryへTest dependencyを持ち込みません。

---

## 10. Full CI Roadmap

### PR

```text
Build
swift-format
SwiftLint
Unit
Architecture
FileSafety
Recovery
```

### Main

```text
Integration
Snapshot
Periphery
```

### Nightly

```text
ASan
TSan
Main Thread Checker
CodeQL
Performance
```

### Release

```text
All critical tests
Release build
codesign verify
notarization verify
staple verify
entitlement verify
smoke launch
```

---

## 11. Release原則

Safety TestをskipしてGreenにすることは禁止します。

Snapshotの1px差よりFile Safety failureを重大として扱います。

Source codeだけでなく、最終的にユーザーがDownloadするRelease Artifactまで検証します。
