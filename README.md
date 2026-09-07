# SchneeGlass

> 好きなフォルダを、Macのデスクトップ上にGlassとして置く。

SchneeGlass は、任意の実フォルダをmacOSデスクトップ上に軽量な半透明Surfaceとして配置し、Finderを開かずにファイルへ触れられるようにするネイティブmacOSアプリです。

## Status

**v0.1 Bootstrap / Architecture phase**

現在は、実装開始前提となるArchitecture・File Safety・Recovery・SPM Module Boundary・初期Domain Contract・CI Guardを構築しています。

現時点で入っているもの:

- `Packages/SchneeGlassKit`
  - Swift 6
  - macOS 15+
  - Compile-time Target Boundaries
- Initial Domain / Application Contracts
- Swift Testing Bootstrap Tests
- App Sandbox Entitlement Baseline
- Architecture Guard
- File Mutation Allowlist Guard
- Public Repository Safety Guard
- GitHub Actions Bootstrap CI

macOS App Target自体は、利用可能なXcode環境で生成・検証後に追加します。未検証の`project.pbxproj`を手書きでCommitしません。

## Product Promise

SchneeGlass v0.1 は意図的に **non-destructive** です。

```text
User-owned source Move      = 0
User-owned source Rename    = 0
User-owned source Delete    = 0
Silent overwrite            = 0
Unknown partial auto-delete = 0
```

v0.1で許可するFilesystem変更は、選択済みFolderへのregular file Copyと、そのCopy中にSchneeGlass自身が作成したstaging fileのinternal commitに限定します。

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

## Bootstrap Test

```bash
swift test --package-path Packages/SchneeGlassKit
bash Scripts/verify-public-repo.sh
bash Scripts/verify-architecture.sh
bash Scripts/verify-file-safety.sh
```

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Testing](TESTING.md)
- [Security](SECURITY.md)
- [Dependencies](DEPENDENCIES.md)
- [Agent Rules](AGENTS.md)
- [Technical Debt](TECH_DEBT.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)

## v0.1 Scope

予定:

- Folder Glass
- Multiple Glass
- One-level Folder Listing
- External Change Refresh
- Regular-file Copy Drop
- Security-scoped Folder Access
- Config Persistence / Backup
- Safe Mode / Recovery
- Window Position Recovery
- Menu Bar
- Global Show/Hide Shortcut

対象外:

- Move
- Rename
- Delete
- Folder Recursive Copy
- Deep Drop
- Git Integration
- Cloud Backend
- Runtime AI
- Private macOS API

---

SchneeGlassはユーザーのファイルを所有しません。

SchneeGlassが使えなくなっても、ユーザーのファイルは通常のmacOSファイルとして残り続けることを最上位原則とします。
