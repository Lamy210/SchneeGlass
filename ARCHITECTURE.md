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

---

## 2. Source of Truth

```text
User filesystem = Source of Truth
SchneeGlass config = Rebuildable metadata
Cache = Disposable
SchneeGlass app = Optional convenience layer
```

SchneeGlass 独自形式へユーザーファイルを格納しません。

SchneeGlass を削除・停止しても、ユーザーは Finder 等から通常のファイルへアクセスできなければなりません。

---

## 3. Local Package / Target構成

Local Swift Package `Packages/SchneeGlassKit` 内の **SPM TargetをArchitecture Boundary** とします。

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

Packageは物理的なコンテナです。

責務境界はTarget dependency graphで強制します。

### 3.1 依存方向

```text
SchneeGlassDomain
  └ Foundation only

FileDomain
  ├ Foundation
  └ SchneeGlassDomain

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
  └ CoreServices / macOS filesystem APIs

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

`SchneeGlassPresentation` から `SchneeGlassFileSystemAdapter` / `SchneeGlassPersistenceAdapter` への直接依存は禁止します。

`SchneeGlassDomain` / `FileDomain` から Presentation / AppKit / Concrete Adapter への依存は禁止します。

---

## 4. Layer Responsibilities

### 4.1 SchneeGlassDomain

Glass自身に閉じたValue Objectを配置します。

配置:

- `GlassID`
- `ResourceFingerprint`
- `FolderSource`
- `GlassPlacement`
- `GlassConfiguration`

禁止:

- SwiftUI
- AppKit
- FSEvents
- Database
- File mutation
- Concrete adapter

### 4.2 FileDomain

Filesystemに関するPureな意味・計画を配置します。

配置:

- `FileKind`
- `FileIdentity`
- `FolderIdentity`
- `GlassItem`
- `FolderSnapshot`
- `StorageLocationKind`
- `StorageCapabilities`
- `DropCandidate`
- `DestinationDescriptor`
- `DropPlan`
- `DropRejection`
- `CopyItemPlan`
- `CopyBatchPlan`

重要:

`FileDomain` にSecurity-Scoped Access Handleを置きません。

`CopyBatchPlan` は「何をどこへCopyするか」というPure Planであり、OS上のAccess Authorizationを保持しません。

Filesystem mutationは禁止します。

### 4.3 SchneeGlassApplication

Domain同士を組み合わせるApplication ContractとUse Caseを配置します。

配置:

- Use Cases
- Ports
- Runtime session orchestration
- Recovery orchestration
- `FolderAccessHandle`
- `AuthorizedCopyBatchRequest`
- `CopyBatchResult`
- `CopyProgress`
- `GlassContentState`
- `InteractionState`

`GlassContentState` / `InteractionState` は `FileDomain` の型をassociated valueとして保持するため、循環依存を避ける目的で `SchneeGlassDomain` ではなくApplication Layerへ配置します。

主要 Ports:

- `FolderSnapshotReading`
- `FolderAccessControlling`
- `FileCopying`
- `ConfigurationPersisting`
- `FileEventStreaming`
- `WindowControlling`

### 4.4 SchneeGlassPresentation

配置:

- `@Observable` Presentation Model
- SwiftUI View
- UI Intent
- User-facing Error Mapping

Viewが行ってよいこと:

- Render
- Intent emit
- Display formatting

Viewから禁止:

- Folder enumeration
- Bookmark resolve
- FSEvents registration
- File mutation
- Config direct write
- Concrete adapter import

### 4.5 SchneeGlassFileSystemAdapter

配置予定:

- `SecurityScopedAccessCoordinator`
- `NativeFolderSnapshotReader`
- `FileEventHub`
- `SafeFileCopyEngine`
- `InternalStagingCommitter`
- `RecoveryMetadataStore`

Runtimeでdestination filesystemに対するmutationを実行できる唯一のTargetです。

### 4.6 SchneeGlassPersistenceAdapter

配置予定:

- `JSONConfigurationStore`
- `ConfigurationBackupStore`
- `AtomicConfigurationWriter`

### 4.7 SchneeGlassMacOSAdapter

配置予定:

- `GlassWindowCoordinator`
- `NSPanel` subclass
- `NSWorkspace` bridge
- Folder picker
- Menu Bar controller

---

## 5. Stateの配置原則

次の状態はPure Glass DomainではなくApplication orchestration stateです。

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

理由:

- `FolderSnapshot`
- `DropPlan`
- `CopyProgress`

など複数Domain/Application Contractを組み合わせるためです。

Primary stateを独立Boolean群で表現しません。

---

## 6. Security-Scoped Access Boundary

Security ScopeはPure FileDomainへ持ち込みません。

```text
FolderSource
   ↓
FolderAccessControlling.acquire
   ↓
FolderAccessHandle
   ↓
Authorized operation
```

`FolderAccessHandle` はApplication Contractです。

ConcreteなBookmark resolve / `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` は `SchneeGlassFileSystemAdapter` が実装します。

Acquire / Releaseは必ずbalanceさせます。

Duplicate releaseはidempotentとし、二重 `stopAccessing...` は行いません。

---

## 7. File Mutation Boundary

v0.1ではユーザー所有sourceに対して以下を禁止します。

```text
Move
Rename
Delete
Replace
Truncate
Write
```

唯一の内部例外は、SchneeGlass自身が現在のCopy operationのために作成したstaging fileを同一destination directory内でfinal nameへcommitするRenameです。

```text
.glass-<operation-id>.partial
              ↓
         final-name.ext
```

この処理は `InternalStagingCommitter` のみ実行できます。

CIのFile Safety Guardでallowlist外の `removeItem` / `moveItem` / `replaceItem` 使用を拒否します。

---

## 8. Copy PlanとAuthorized Executionの分離

循環依存とSecurity Context漏洩を防ぐため、Copyを2段階に分離します。

### Pure Plan — FileDomain

```text
CopyBatchPlan
├ destination: DestinationDescriptor
└ items: [CopyItemPlan]
```

### Authorized Execution — SchneeGlassApplication

```text
AuthorizedCopyBatchRequest
├ plan: CopyBatchPlan
└ destinationAccess: FolderAccessHandle
```

これにより `FileDomain` は `SchneeGlassApplication` へ逆依存しません。

---

## 9. Copy Semantics

v0.1はSequential Copyです。

```text
maxConcurrentCopies = 1
```

Batch全件をpreflightし、決定的rejectが1件でもあれば0件CopyでBatch全体をrejectします。

Runtime failureは最初の失敗で停止します。

Batchはtransactionalではありません。

```text
A success
B success
C failure
D not attempted
```

A/Bの成功済みCopyを自動削除してrollbackしてはいけません。

---

## 10. FSEvents

FSEventsはauthoritative stateとして扱いません。

```text
event = "何かが変化した可能性がある"
```

必ずdirect-child snapshotを再取得します。

Startup順序:

```text
1. Security scope acquire
2. FSEvent stream create
3. FSEvent stream start
4. Initial snapshot start
5. Snapshot中のeventはdirty=true
6. Initial snapshot commit
7. dirtyなら再snapshot
8. Steady state
```

`MustScanSubDirs` / dropped events / root change相当時はfull direct-child rescanとします。

---

## 11. Persistence / Recovery

v0.1は `Codable JSON` を使用します。

```text
Application Support/<bundle-id>/
├ Configuration/
│  ├ config.json
│  └ Backups/
└ Recovery/
   └ pending-copies.json
```

原則:

- Configはatomic write
- Valid backup最大5世代
- Silent automatic rollback禁止
- Config corruptionはRecovery/Safe Modeへ遷移
- Unknown `.glass-*` fileは自動削除禁止

---

## 12. Windowing

v0.1:

- `NSApplication.ActivationPolicy.regular`
- Dock icon表示
- `NSPanel` + `NSHostingView`
- Header drag areaのみWindow移動に利用
- All Spacesはopt-in
- Private Space API禁止

保存先displayが存在しない場合はmain displayの`visibleFrame`内へRecoveryします。

---

## 13. Architecture Enforcement

CIで最低限以下を検出します。

- Domain → SwiftUI/AppKit/CoreServices/GRDB import
- Presentation → FileSystem/Persistence Concrete Adapter import
- Private CGS symbol
- Filesystem mutation APIのallowlist外利用
- `@unchecked Sendable` の無承認利用
- Swift source内のIssue番号なしTODO/FIXME
- Public repositoryへのcredential-like file混入
- 高確度Secret Pattern

Architectureは文書だけでなくCompiler/CIで強制します。

---

## 14. Bootstrap方針

初期段階ではAdapterにFakeの実装を詰め込みません。

最初に以下を安定させます。

```text
SPM dependency graph
↓
Domain contracts
↓
Application ports
↓
Tests
↓
Safety/Architecture CI guards
↓
Concrete macOS adapters
```

Concrete implementationの都合でDomain/Dependency方向を変更してはいけません。

変更が必要な場合はADRを追加し、Architecture Reviewを行います。
