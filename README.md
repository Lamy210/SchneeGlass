# SchneeGlass

> 好きなフォルダを、Macのデスクトップ上にGlassとして置く。

SchneeGlass は、任意の実フォルダをmacOSデスクトップ上に軽量な半透明Surfaceとして配置し、Finderを開かずにファイルへ触れられるようにするネイティブmacOSアプリです。

## Status

**v0.1 Core / Recovery / Automated Quality Baseline Complete — Production Validation Pending**

v0.1の主要機能、Recovery導線、CI diagnostics、Developer ID signing / notarization / immutable release publicationのコードは`main`へ実装済みです。現在のRelease blockerは、production credential・repository governance・実signed candidate・Manual QAを用いた運用検証です。

実装済み:

- Swift 6 / macOS 15+ / App SandboxのmacOS App Target
- Compile-time Architecture Boundary
- Security-scoped Folder Access
- One-level Folder Snapshot / 500-item safety limit
- 500-item Folder Snapshot Performance Baseline
  - relevant PR / weekly / manual workflow
  - monotonic clockによる3-run measurement
  - `worst < 0.5s` regression ceiling
  - PR #39最終実測: average `0.055926s` / worst `0.059213s`
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
  - app-owned state directory / leaf symlinkをfollowしないphysical topology enforcement
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
- AddressSanitizer package tests
- scheduled/manual ThreadSanitizer package tests
- scheduled/manual/default-branch Swift CodeQL v4 analysis
- unsigned Release Candidate validation + SHA-256 manifest
- production credential contract / credential-free fail-closed preflight
- Developer ID signed Release archive workflow
- post-sign codesign / entitlement / Hardened Runtime verification
- Apple `notarytool` Accepted-state verification
- stapler / Gatekeeper verification
- signed/notarized candidate artifact
- strict `RELEASE_EVIDENCE.txt` schema v1
  - required keys exactly once
  - unknown/malformed key rejection
  - final signed ZIP由来のbundle identifier / version / build
  - exact source commit SHA
- exact Production Release Candidate workflow identity validation
  - workflow name + `.github/workflows/production-release.yml` path
  - `workflow_dispatch` / `main` / completed-success
- public Release build-number monotonicity gate
- Manual QA後のimmutable GitHub Release promotion workflow

v0.1で残っているRelease blocker:

- `production-release` environmentへ実Developer ID / App Store Connect credentialを設定
- Repository release immutabilityを有効化
- `main` branch protection / required CIなどRelease governanceを確認
- 最初のcredentialed signed/notarized candidateを成功させる
- `docs/MANUAL_QA.md`をsigned candidateで完走する
- 最初のimmutable v0.1 GitHub Releaseをpublishする

コード実装済みと運用検証待ちを混同しないこと。詳細は [`docs/IMPLEMENTATION_PLAN.md`](docs/IMPLEMENTATION_PLAN.md) と Issue #33 を参照してください。

## Product Promise

SchneeGlass v0.1 は意図的に **non-destructive** です。

```text
User-owned source Move      = 0
User-owned source Rename    = 0
User-owned source Delete    = 0
Silent overwrite            = 0
Unknown partial auto-delete = 0
```

v0.1で許可するuser-visible Filesystem変更は、選択済みFolderへのregular file Copyと、そのCopy中にSchneeGlass自身が作成したstaging fileのinternal commit、明示Recoveryでownership proofが成立したapp-owned stagingの処理に限定します。Configuration / Pending CopyなどSchneeGlass-owned metadataはApplication Support配下だけで管理し、physical directory / regular-file boundaryを通して保存します。RecoveryのFinder inspectionとDestination Reconnectはuser-owned file内容を変更しません。

## Architecture

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

Concrete filesystem / persistence / macOS APIはAdapterへ閉じ、Presentationから直接触りません。`SchneeGlassPOSIXSupport`はFoundation / Darwinだけに依存するshared infrastructure boundaryで、SchneeGlass-owned metadataのphysical filesystem semanticsだけを共有します。

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
bash Scripts/verify-release-metadata.sh
bash Scripts/verify-production-release-preflight.sh
```

GitHub Actionsでは上記に加えて、AddressSanitizer、macOS 15 compatibility build、Xcode 26.6 Debug / Release app build、Sandbox baseline、unsigned artifact、scheduled ThreadSanitizer、Swift CodeQL v4、500-item Snapshot Performance Baselineを継続検証します。

## Documentation

- [Architecture](ARCHITECTURE.md)
- [Testing](TESTING.md)
- [Security](SECURITY.md)
- [Dependencies](DEPENDENCIES.md)
- [Release Policy](RELEASE.md)
- [Install](docs/INSTALL.md)
- [Manual QA](docs/MANUAL_QA.md)
- [Agent Rules](AGENTS.md)
- [Technical Debt](TECH_DEBT.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)

## v0.1 Scope

実装済み:

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
