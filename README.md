# SchneeGlass

> 好きなフォルダを、Macのデスクトップ上にGlassとして置く。

SchneeGlass は、任意の実フォルダをmacOSデスクトップ上に軽量な半透明Surfaceとして配置し、Finderを開かずにファイルへ触れられるようにするネイティブmacOSアプリです。

## Status

**v0.1 Core Feature / Recovery Complete / Quality & Release Hardening**

Bootstrap段階とv0.1必須Recovery導線は完了し、現在の`main`には実macOS Appと主要利用・障害復旧フローが接続されています。

実装済み:

- Swift 6 / macOS 15+ / App SandboxのmacOS App Target
- Compile-time Architecture Boundary
- Security-scoped Folder Access
- One-level Folder Snapshot / 500-item safety limit
- FSEventsによるExternal Change Refresh
- Multiple Glass / Runtime Session lifecycle
- Glass作成・起動時復元・削除
- Open / Reveal in Finder
- Regular-file Safe Copy Drag & Drop
  - source Move / Rename / Deleteなし
  - silent overwriteなし
  - app-owned staging + recovery metadata
  - partial-success / crash recovery semantics
- Pending Copy Recovery Center
  - fresh filesystem assessment / action planning
  - stale UI stateをmutation authorityにしないexplicit execution
  - ownership proof再検証付きapp-owned staging cleanup
  - Copy / Recovery mutationの相互排他
  - identity検証付きDestination Reconnect
  - stale reconnect rejection
  - `Show Incomplete Copy` / `Show Final File`によるread-only manual inspection
  - ambiguous / ownership-unproven stateではauto-deleteしない
- Atomic JSON Configuration Persistence
  - valid backup最大5世代
  - corrupt currentをsilent overwriteしない
  - explicit configuration recovery
- Desktop上の1 Glass = 1 `NSPanel`
- move / resize placement persistence
- off-screen frame recovery
- Menu Bar controls
- Reset Glass Positions
- SettingsからのConfiguration Backup Recovery
- User-customizable Global Show / Hide Shortcut
- Public Repository / Architecture / File Safety CI guards
- Xcode 26.6 Debug / Release build CI
- macOS 15 compatibility build CI
- unsigned CI app artifact生成

v0.1で残っている主要項目:

- Quality / Diagnostics CIの拡張
- 配布用Signing / Notarization / Release Pipeline
- release/install documentation
- manual QAの仕上げ

詳細な進捗は [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) を参照してください。

## Product Promise

SchneeGlass v0.1 は意図的に **non-destructive** です。

```text
User-owned source Move      = 0
User-owned source Rename    = 0
User-owned source Delete    = 0
Silent overwrite            = 0
Unknown partial auto-delete = 0
```

v0.1で許可するFilesystem変更は、選択済みFolderへのregular file Copyと、そのCopy中にSchneeGlass自身が作成したstaging fileのinternal commit、明示Recoveryでownership proofが成立したapp-owned stagingの処理に限定します。RecoveryのFinder inspectionとDestination Reconnectはuser-owned file内容を変更しません。

## Architecture

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

Concrete filesystem / persistence / macOS APIはAdapterへ閉じ、Presentationから直接触りません。

詳細は [`ARCHITECTURE.md`](ARCHITECTURE.md) を参照してください。

## Public Repository Safety

このRepositoryはPublicです。

Commitしてはいけないもの:

- API Key / Token / Secret
- Private Key / Signing Material
- `.env`
- Security-scoped Bookmark Raw Data
- 実在する会社・顧客の内部情報
- 個人・会社環境の絶対Pathを含むFixture
- Private Diagnostics Dump

Sample/Test Dataには架空値だけを使用します。

詳細は [`SECURITY.md`](SECURITY.md) と [`AGENTS.md`](AGENTS.md) を参照してください。

## Development Verification

```bash
swift test --package-path Packages/SchneeGlassKit
bash Scripts/verify-public-repo.sh
bash Scripts/verify-architecture.sh
bash Scripts/verify-file-safety.sh
```

GitHub Actionsでは上記に加えて、macOS 15 compatibility buildとXcode 26.6 Debug / Release app build、Sandbox baseline、unsigned artifact生成を継続検証します。

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Testing](TESTING.md)
- [Security](SECURITY.md)
- [Dependencies](DEPENDENCIES.md)
- [Agent Rules](AGENTS.md)
- [Technical Debt](TECH_DEBT.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)

## v0.1 Scope

実装済み / 実装中:

- Folder Glass
- Multiple Glass
- One-level Folder Listing
- External Change Refresh
- Regular-file Copy Drop
- Security-scoped Folder Access
- Config Persistence / Backup
- Explicit Configuration Recovery
- Pending Copy Recovery Center / Explicit Safe Recovery
- Recovery Destination Reconnect
- Read-only Recovery Manual Inspection
- Window Position Recovery
- Menu Bar
- Global Show/Hide Shortcut

対象外:

- User-owned source Move
- User-owned source Rename
- User-owned source Delete
- Folder Recursive Copy
- Deep Drop
- Git Integration
- Cloud Backend
- Runtime AI
- Private macOS API

---

SchneeGlassはユーザーのファイルを所有しません。

SchneeGlassが使えなくなっても、ユーザーのファイルは通常のmacOSファイルとして残り続けることを最上位原則とします。
