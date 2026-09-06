# SchneeGlass Architecture

## 1. 目的

SchneeGlass の Architecture は、次を同時に満たすことを目的とします。

- macOS ネイティブ UX
- ユーザーファイルの安全性
- Swift 6 concurrency safety
- Recovery / reversibility
- 一人 + AI 駆動でも責務境界を壊しにくいこと
- v0.1 を小さく保ちながら v0.2+ へ拡張可能であること

採用方式は次の組み合わせです。

```text
Modular Monolith
+ Ports & Adapters
+ Unidirectional Presentation Flow
+ Explicit State Machines
+ Command-oriented File Operations
+ Compile-time Target Boundaries
```

TCA、Service Locator、Global Event Bus、Microservice、Plugin Framework は v0.1 では採用しません。

## 2. Source of Truth

```text
User filesystem = Source of Truth
SchneeGlass config = Rebuildable metadata
Cache = Disposable
SchneeGlass app = Optional convenience layer
```

SchneeGlass 独自形式へユーザーファイルを格納しません。

## 3. Target 構成

Local Swift Package `SchneeGlassKit` 内の SPM Target を Architecture Boundary とします。

```text
SchneeGlassDomain
FileDomain
SchneeGlassApplication
SchneeGlassPresentation
SchneeGlassDesignSystem
SchneeGlassFileSystemAdapter
SchneeGlassPersistenceAdapter
SchneeGlassMacOSAdapter
```

### 依存方向

```text
SchneeGlassDomain
  └ Foundation only

FileDomain
  ├ Foundation
  └ SchneeGlassDomain (必要時のみ)

SchneeGlassApplication
  ├ SchneeGlassDomain
  └ FileDomain

SchneeGlassDesignSystem
  └ SwiftUI

SchneeGlassPresentation
  ├ SchneeGlassApplication
  ├ SchneeGlassDomain
  ├ FileDomain
  └ SchneeGlassDesignSystem

SchneeGlassFileSystemAdapter
  ├ SchneeGlassApplication
  ├ FileDomain
  ├ Foundation
  └ CoreServices

SchneeGlassPersistenceAdapter
  ├ SchneeGlassApplication
  ├ SchneeGlassDomain
  └ Foundation

SchneeGlassMacOSAdapter
  ├ SchneeGlassApplication
  ├ SchneeGlassDomain
  ├ AppKit
  └ Foundation
```

`SchneeGlassPresentation` から Concrete filesystem/persistence adapter への直接依存は禁止します。

## 4. Layer Responsibilities

### SchneeGlassDomain

配置:

- `GlassID`
- `GlassConfiguration`
- `GlassPlacement`
- `GlassContentState`
- `InteractionState`

禁止:

- SwiftUI
- AppKit
- FSEvents
- DB
- File mutation

### FileDomain

配置:

- `FileKind`
- `FileIdentity`
- `FolderIdentity`
- `FolderSnapshot`
- `DropPlan`
- `DropRejection`
- Copy request/result value objects
- Domain errors

Filesystem mutation は行いません。

### SchneeGlassApplication

配置:

- Use Cases
- Ports
- Runtime session orchestration
- Recovery orchestration

主要 Ports:

- `FolderSnapshotReading`
- `FolderAccessControlling`
- `FileCopying`
- `ConfigurationPersisting`
- `FileEventStreaming`
- `WindowControlling`

### SchneeGlassPresentation

配置:

- `@Observable` presentation models
- SwiftUI Views
- UI intents
- User-facing error mapping

View から Folder enumeration、Bookmark resolve、FSEvents registration、File mutation を行ってはいけません。

### SchneeGlassFileSystemAdapter

配置:

- `SecurityScopedAccessCoordinator`
- `NativeFolderSnapshotReader`
- `FileEventHub`
- `SafeFileCopyEngine`
- `InternalStagingCommitter`
- `RecoveryMetadataStore`

Runtime でユーザーの destination filesystem に対する mutation を行える唯一の target とします。

## 5. File Mutation Boundary

v0.1 でユーザー所有 source に対して以下を禁止します。

```text
Move
Rename
Delete
Replace
Truncate
Write
```

唯一の内部例外は、SchneeGlass 自身が現在の Copy operation のために作成した staging file を同一 destination directory 内で final name へ commit する rename です。

```text
.glass-<operation-id>.partial
              ↓
         final-name.ext
```

この処理は `InternalStagingCommitter` のみ実行できます。

## 6. Security-Scoped Access

`SecurityScopedAccessCoordinator` actor が次を一元管理します。

```text
bookmark resolve
→ stale check
→ startAccessingSecurityScopedResource
→ FolderAccessHandle 登録
→ resource usage
→ watcher stop
→ stopAccessingSecurityScopedResource
→ handle 削除
```

Acquire/Release は必ず balance させます。Duplicate release は idempotent とし、二重 `stopAccessing...` は行いません。

## 7. FSEvents

FSEvents は authoritative state として扱いません。

```text
event = "何かが変化した可能性がある"
```

必ず direct-child snapshot を再取得します。

Startup 順序:

```text
1. Security scope acquire
2. FSEvent stream create
3. FSEvent stream start
4. Initial snapshot start
5. Snapshot 中の event は dirty=true
6. Initial snapshot commit
7. dirty なら再 snapshot
8. Steady state
```

`MustScanSubDirs` / dropped events / root change 相当時は full direct-child rescan とします。

## 8. Copy Semantics

v0.1 は sequential copy (`maxConcurrentCopies = 1`) とします。

Batch 全件を preflight して deterministic rejection が1件でもあれば、0件の copy で batch 全体を reject します。

Runtime failure は最初の失敗で停止します。Batch は transactional ではありません。

```text
A success
B success
C failure
D not attempted
```

A/B の成功済み copy を自動削除して rollback してはいけません。

## 9. Persistence / Recovery

v0.1 は `Codable JSON` を使用します。

```text
Application Support/<bundle-id>/
├ Configuration/
│  ├ config.json
│  └ Backups/
└ Recovery/
   └ pending-copies.json
```

- Config は atomic write
- Valid backup 最大5世代
- Silent automatic rollback 禁止
- Config corruption は Recovery/Safe Mode へ遷移
- Unknown `.glass-*` file は自動削除禁止

## 10. UI State

Primary state を boolean 群で表現しません。

```text
GlassContentState
├ loading
├ ready(snapshot)
├ empty(snapshot)
├ unavailable(reason)
└ failed(error)

InteractionState
├ idle
├ hovered
├ dropValid(plan)
├ dropInvalid(reason)
└ copying(progress)
```

## 11. Windowing

v0.1:

- `NSApplication.ActivationPolicy.regular`
- Dock icon 表示
- `NSPanel` + `NSHostingView`
- Header drag area のみ window movement に利用
- All Spaces は opt-in
- Private Space API 禁止

保存先 display が存在しない場合は main display の `visibleFrame` 内へ recovery します。

## 12. Architecture Enforcement

CI で最低限以下を検出します。

- Domain → SwiftUI/AppKit import
- Presentation → FileSystem/Persistence concrete adapter import
- Private CGS symbol
- Filesystem mutation API の allowlist 外利用
- `@unchecked Sendable` の無承認利用
- Issue 番号なし TODO/FIXME

Architecture は文書だけでなく Compiler/CI で強制します。
