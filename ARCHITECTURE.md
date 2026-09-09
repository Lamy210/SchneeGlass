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
SchneeGlassPOSIXSupport
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

SchneeGlassPOSIXSupport
  ├ Foundation
  └ Darwin

SchneeGlassPresentation
  ├ SchneeGlassApplication
  ├ SchneeGlassDomain
  ├ FileDomain
  └ SchneeGlassDesignSystem

SchneeGlassFileSystemAdapter
  ├ SchneeGlassApplication
  ├ FileDomain
  ├ SchneeGlassPOSIXSupport
  ├ Foundation
  └ CoreServices / macOS filesystem APIs

SchneeGlassPersistenceAdapter
  ├ SchneeGlassApplication
  ├ SchneeGlassDomain
  ├ SchneeGlassPOSIXSupport
  └ Foundation

SchneeGlassMacOSAdapter
  ├ SchneeGlassApplication
  ├ SchneeGlassDomain
  ├ AppKit
  └ Foundation
```

`SchneeGlassPresentation` から `SchneeGlassFileSystemAdapter` / `SchneeGlassPersistenceAdapter` / `SchneeGlassPOSIXSupport` への直接依存は禁止します。

`SchneeGlassDomain` / `FileDomain` から Presentation / AppKit / Concrete Adapter / `SchneeGlassPOSIXSupport` への依存は禁止します。

`SchneeGlassPOSIXSupport` から Domain / Application / Presentation / Concrete Adapter への依存は禁止します。

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
- `FolderAccessAcquisition`
- `AuthorizedCopyBatchRequest`
- `CopyBatchResult`
- `CopyProgress`
- `GlassContentState`
- `InteractionState`
- `FileEvent`

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

### 4.5 SchneeGlassPOSIXSupport

Darwin / Foundationだけに依存するshared infrastructure primitiveです。

配置:

- `PhysicalStateStore`
- app-owned physical directory traversal
- `O_NOFOLLOW` regular-file read
- same-directory atomic state write
- physical regular-file listing / removal

禁止:

- Domain model
- Application use case
- Presentation state
- Security-Scoped Bookmark orchestration
- user-owned file mutation policy
- Concrete Adapter import

このTargetはPersistenceAdapterとFileSystemAdapterが同じPOSIX safety semanticsを共有するためだけに使用します。

### 4.6 SchneeGlassFileSystemAdapter

Read Pathで実装済み:

- `SecurityScopedAccessCoordinator`
- `NativeFolderSnapshotReader`
- `FileEventHub`

Safe Copyで実装済み:

- `PinnedDropCopyPipeline`
- `SafeFileCopyEngine`
- `SourceFileLeaseRegistry`
- `DestinationDirectoryLeaseRegistry`
- `PinnedDestinationStagingCommitter`
- `InternalStagingCommitter`（internal test/support）
- `JSONPendingCopyStore`

Runtimeでdestination filesystemに対するuser-visible copy mutationを実行できる唯一のConcrete Adapterです。

Production Safe Copyはsource inodeとdestination directoryをdescriptorでpinし、staging作成を`openat(... O_EXCL | O_NOFOLLOW)`、final commitを同一directory descriptor上の`renameatx_np(... RENAME_EXCL)`で実行します。Pathnameは表示・計画上の情報であり、mutation authorityそのものとして扱いません。詳細はADR 0008を参照します。

Pending-copy metadataのapp-owned state mutationは`SchneeGlassPOSIXSupport`へ委譲します。

### 4.7 SchneeGlassPersistenceAdapter

配置:

- `JSONConfigurationStore`
- Configuration backup / restore orchestration

Configuration-owned filesystem I/Oは`SchneeGlassPOSIXSupport`へ委譲します。

### 4.8 SchneeGlassMacOSAdapter

配置:

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
FolderAccessAcquisition
   ├ FolderAccessHandle
   └ refreshedSource?
   ↓
Authorized operation
```

`FolderAccessHandle` はApplication Contractです。

ConcreteなBookmark resolve / `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` は `SchneeGlassFileSystemAdapter` が実装します。

Acquire / Releaseは必ずbalanceさせます。

Duplicate releaseはidempotentとし、二重 `stopAccessing...` は行いません。

stale bookmarkをresolveした場合は`refreshedSource`を返し、Application/Persistence側で新しいBookmarkを永続化できるようにします。

Fingerprintが利用可能で、保存済みFingerprintと現在のResourceが明確に異なる場合は、同じPathを別Resourceとして暗黙採用せず`resourceReplacementDetected`として扱います。

---

## 7. Folder Snapshot / File Classification

Folder Snapshotは登録Folderの**直下1階層だけ**を列挙します。

```text
hidden files            → default skip
subdirectory descendants → skip
package descendants      → skip
maximum displayed items  → 500
```

501件目を観測した時点で列挙を打ち切り、`isTruncated = true`を返します。

File classificationはmacOS上の実挙動を考慮し、次の順序とします。

```text
1. Physical symbolic link (FileManager file attributes)
2. Finder Alias
3. Package
4. Directory
5. Regular File
6. Unsupported
```

`URLResourceValues.isAliasFile`はsymlinkでもAlias相当として見える場合があるため、symlinkは物理File Attributeを先に確認します。

Display NameからFilesystem Pathを再構築せず、操作には常に実URLを使用します。

---

## 8. File Mutation Boundary

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
.schneeglass-copy-<operation-id>.partial
                   ↓
              final-name.ext
```

Productionでは`DestinationDirectoryLeaseRegistry`が物理destination directoryをpinし、`PinnedDestinationStagingCommitter`だけがそのdescriptor上で`RENAME_EXCL`付きfinal commitを実行します。`InternalStagingCommitter`はfocused internal test/support pathとして残しますが、production compositionからは使用しません。

SchneeGlass-owned metadata (`Configuration` / `FileOperations`) のmutationはuser-owned mutationとは別boundaryとして`SchneeGlassPOSIXSupport.PhysicalStateStore`だけに限定します。

CIのFile Safety Guardでallowlist外の `removeItem` / `moveItem` / `replaceItem` / `mkdirat` / `renameat` / `renameatx_np` / `unlinkat` / mutation用`O_CREAT` 使用を拒否します。

---

## 9. Copy PlanとAuthorized Executionの分離

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

## 10. Copy Semantics

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

## 11. FSEvents

FSEventsはauthoritative stateとして扱いません。

```text
event = "何かが変化した可能性がある"
```

Applicationへ渡すEventも、Path差分ではなく次の意味だけを持ちます。

```text
FileEvent.changed
  → 通常変更。Snapshot refreshが必要

FileEvent.requiresFullRescan
  → MustScanSubDirs / KernelDropped / UserDropped
  → Incremental assumptionを捨ててFull direct-child snapshot

FileEvent.rootChanged
  → watched root自体のMove/Delete/Identity変化
  → Access/Identityを再検証してから表示
```

`rootChanged`は同一Eventにdrop flagが含まれていても優先します。

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

`FileEventHub`は`WatchRoot` + `FileEvents`を使用しますが、個別Path EventをDomain上のauthoritative diffとして公開しません。

Integration TestではEvent件数をassertせず、実Temporary Folderへ変更を加え、eventual notificationを確認します。

---

## 12. Persistence / Recovery

v0.1は `Codable JSON` を使用します。

```text
Application Support/<bundle-id>/
├ Configuration/
│  ├ config.json
│  ├ Backups/
│  └ Preserved/
└ FileOperations/
   └ pending-copies.json
```

原則:

- Configはatomic write
- Valid backup最大5世代
- Silent automatic rollback禁止
- Config corruptionはRecovery/Safe Modeへ遷移
- Unknown `.glass-*` fileは自動削除禁止
- app-owned root / descendant directoryはphysical directoryのみ
- state leafは`O_NOFOLLOW`でopenしたphysical regular fileのみ
- unsafe owned-state topologyはfail-closed

詳細はADR 0007を参照します。

---

## 13. Windowing

v0.1:

- `NSApplication.ActivationPolicy.regular`
- Dock icon表示
- `NSPanel` + `NSHostingView`
- Header drag areaのみWindow移動に利用
- All Spacesはopt-in
- Private Space API禁止

保存先displayが存在しない場合はmain displayの`visibleFrame`内へRecoveryします。

---

## 14. Architecture Enforcement

CIで最低限以下を検出します。

- Domain → SwiftUI/AppKit/CoreServices/GRDB/POSIXSupport import
- Presentation → FileSystem/Persistence/POSIXSupport import
- POSIXSupport → Domain/Application/Presentation/Concrete Adapter import
- Private CGS symbol
- Filesystem mutation APIのallowlist外利用
- `@unchecked Sendable` の無承認利用
- Swift source内のIssue番号なしTODO/FIXME
- Public repositoryへのcredential-like file混入
- 高確度Secret Pattern

Architectureは文書だけでなくCompiler/CIで強制します。

---

## 15. Bootstrap / CI方針

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

CIは2つのToolchain役割を分離します。

```text
Compatibility
  → macOS 15 runner
  → Deployment Target下限側の互換性確認

Canonical
  → macOS 26 runner
  → Xcode 26.6 / Swift 6.3
  → Architecture / Safety / Public Repo Guards
  → Full Swift Package Tests
```

Concrete implementationの都合でDomain/Dependency方向を変更してはいけません。

変更が必要な場合はADRを追加し、Architecture Reviewを行います。