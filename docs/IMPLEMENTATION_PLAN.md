# SchneeGlass v0.1 Implementation Plan

このドキュメントは `ARCHITECTURE.md` の設計を実装順へ落としたものです。

このドキュメントは **v0.1実装・旧Developer ID配布設計の履歴**を保持する資料です。現在の配布方針は[ADR-0011](adr/0011-adhoc-distribution-without-developer-id.md)と[現行Release Policy](../RELEASE.md#active-v02-ad-hoc-release-path-adr-0011)を優先し、Developer ID / notarization / `production-release` の旧経路を実行しません。現在の未完了ゲートは[#519](https://github.com/Lamy210/SchneeGlass/issues/519)、[#547](https://github.com/Lamy210/SchneeGlass/pull/547)、[#520](https://github.com/Lamy210/SchneeGlass/issues/520)です。

StatusはRepositoryの実装とmerged PRを基準に更新します。古い計画上の`NOT STARTED`を根拠に重複実装しないこと。

## Phase 0 — Architecture Baseline

### TASK-000 — 設計Baseline

Status: **DONE**

主な完了内容:

- Architecture / Security / Testing policy
- Dependency policy
- Agent rules
- Tech debt policy
- ADR baseline
- Compile-time package boundaries

---

## Phase 1 — Bootstrap

### TASK-001 — Project / Package Bootstrap

Status: **DONE**

完了内容:

- `Packages/SchneeGlassKit/Package.swift`
- macOS 15 platform declaration
- Swift 6 language mode
- SPM architecture targets
- `SchneeGlass.xcodeproj`
- Local package linkage
- App Sandbox entitlement linkage
- Debug / Release app build verification
- macOS 15 compatibility build
- unsigned CI app artifact
- Architecture / File Safety / Public Repository guards

---

## Phase 2 — Core Domain / Application

### TASK-002 — Domain Contracts

Status: **DONE for v0.1 scope**

実装済み:

- Glass / Folder / File identity models
- `GlassPlacement` / `GlassConfiguration`
- one-level `FolderSnapshot`
- File classification
- Drop / Copy plan models
- collision and destination capability modeling
- v0.1 invariants and failure-state tests

### TASK-003 — Application Ports / Use Cases

Status: **DONE for current v0.1 flows**

実装済み:

- Folder access / event / snapshot ports
- Create Glass orchestration
- Runtime Session lifecycle
- startup restore
- Remove Glass
- Open / Reveal boundary
- Drop planning / authorized copy execution
- placement persistence / reset
- configuration recovery use case
- Pending Copy recovery / reconnect / read-only inspection use cases
- fake / spy ports for application tests

追加UseCaseは新しいRelease / post-v0.1要件に合わせて個別追加する。

---

## Phase 3 — macOS / Filesystem Adapters

### TASK-004 — Security Scoped Access
Status: **DONE**

- acquire / release lifecycle
- stale bookmark refresh
- security-scoped bookmarkをprimary persistent resource referenceとして使用
- restart-safe supplemental identityとして`PersistentFolderIdentity(volumeUUIDString, documentIdentifier)`を使用
- live operationではdescriptor-derived `RuntimeDirectoryIdentity(st_dev, st_ino)`をprimary identityとして使用
- POSIX runtime identity取得不可時のみFoundation `ResourceFingerprint`をcompatibility fallbackとして使用
- resource replacement detection
- failure cleanup

### TASK-005 — Folder Snapshot Reader
Status: **DONE**

- direct-child only
- hidden item filtering
- 500-item display limit
- symlink / alias / package / directory / regular classification
- snapshot root continuityはPOSIX runtime identityをprimary、Foundation root fingerprintをfallbackとして検証
- 500-item performance baseline
  - 501 direct-child fixture
  - 3-run measurement
  - monotonic clock (`ProcessInfo.systemUptime`)
  - regression ceiling `worst < 0.5s`
  - weekly / manual / relevant-PR workflow

PR #39導入時の最終GitHub-hosted macOS 26 / Xcode 26.6実測:

```text
average = 0.055926s
worst   = 0.059213s
```

### TASK-006 — File Event Hub
Status: **DONE for v0.1**

- FSEvents subscription lifecycle
- changed / requiresFullRescan / rootChanged abstraction
- explicit stop
- Runtime Session refresh integration

### TASK-007 — Drop Planner
Status: **DONE for regular-file v0.1 scope**

- read-only native inspection
- pure DropPlanner
- collision / same-directory / cloud-placeholder rejection
- case-sensitivity handling
- perform-time re-plan
- destination runtime identityをplanning前後で再検証
- symbolic-link destinationをphysical directoryとして扱わずplanning段階でreject
- safe destination commit capabilityをexecution contractと整合

### TASK-008 — Recovery Metadata Store
Status: **DONE**

- `PendingCopyRecord`
- atomic JSON metadata persistence
- scoped remove
- ownership metadata
- recovery assessment foundation

### TASK-009 — Safe File Copy Engine
Status: **DONE for regular-file v0.1 scope**

- sequential copy
- preflight before mutation
- app-owned staging
- size verification
- internal staging commit
- no overwrite
- partial-success semantics
- fault-injection / real-filesystem safety tests
- production source inode / destination directory descriptor pinning
- destination leaseはruntime POSIX identityをprimary authorityとして検証
- Foundation directory identifiersはfallback proofが必要な場合のみ取得・比較

---

## Phase 4 — Persistence / Recovery

### TASK-010 — Configuration Store
Status: **DONE**

- schema-versioned Codable JSON
- atomic write
- valid backup最大5世代
- corrupt/future currentを通常saveで上書きしない
- explicit backup restore
- corrupt current preserve
- unsafe backup identifier rejection
- legacy schema-v1 `source.fingerprint`をdecode可能のまま維持し、新規saveではboot-local fingerprintを永続化しない

### TASK-011 — Startup / Recovery Coordinator
Status: **DONE for v0.1**

完了内容:

- startup best-effort Glass restore
- per-Glass restore failure isolation
- stale bookmark refresh
- explicit Configuration Backup Recovery UI
- recovery中のconfiguration mutation / copy guards
- Desktop panel quiescence during configuration recovery
- Pending Copy Recovery Center UI
- fresh recovery assessment / pure action planning
- stale UI assessmentをmutation authorityにしないexplicit execution
- ownership proof再検証付きapp-owned staging cleanup
- Copy / Recovery mutationのApplication-level相互排他
- destination reconnect
  - folder picker後のrecord/config再load
  - saved / selected双方の`PersistentFolderIdentity` exact-match validation
    - `volumeUUIDString`
    - `documentIdentifier`
  - boot/session-local `ResourceFingerprint`をreconnect authorityとして使用しない
  - persistent identity dimension不足時はfail-closed
  - stale reconnect rejection
  - security-scoped access validation
- read-only manual inspection
  - `Show Incomplete Copy`
  - `Show Final File`
  - Finder表示直前のfresh assessment / action再判定
- ambiguous / ownership-unproven stateではauto-deleteしない
- final user-visible fileのRecovery mutation禁止

---

## Phase 5 — macOS UI

### TASK-012 — Windowing
Status: **DONE for v0.1**

- 1 Glass = 1 `NSPanel`
- placement persistence
- multi-display recovery
- reset positions
- show-on-all-spaces handling

### TASK-013 — Glass Presentation
Status: **DONE for v0.1 core**

- Workspace preview
- Desktop Glass surface
- loading / empty / unavailable / failure states
- file listing
- D&D copy interaction / progress feedback

### TASK-014 — Open / Finder Integration
Status: **DONE**

- Open
- Reveal in Finder
- Remove Glass without source mutation
- Recovery manual inspection in Finder

### TASK-015 — Menu Bar / Global Shortcut
Status: **DONE**

- Menu Bar entry
- Add / Show All / Hide All
- Reset Glass Positions
- Settings / Quit
- user-customizable Global Show / Hide Shortcut
- no default shortcut occupation
- no Accessibility permission requirement
- hidden-state preservation across workspace sync

---

## Phase 6 — Quality / Release

### TASK-016 — Static Architecture / Safety Gates

Status: **ACTIVE BASELINE**

実装済み:

- Public Repository Guard
- Architecture Guard
- File Safety mutation allowlist

新しいmutation APIを追加する場合は同一PRでallowlist rationaleとSafety Testを更新する。

### TASK-017 — CI / Diagnostics

Status: **DONE for v0.1 automated baseline**

現在のCI:

- macOS 26 / Xcode 26.6 toolchain verification
- changed-Swift strict `swift-format` gate
  - pull requestはcheckout時点のbase branchとのmerge-baseを基準にする
  - 通常pushは`github.event.before`を基準にする
  - newly-created refはdefault branchとのmerge-baseへfallbackする
  - added / copied / modified / renamedされた`.swift`だけをlintし、既存repository全体のformat debtは同一PRへ持ち込まない
- Swift Package tests
- pull request時のAddressSanitizer package tests
- scheduled/manual ThreadSanitizer package tests
- Debug app build
- Release app build
- macOS 15 compatibility package tests / app build
- Public Repository Guard
- Architecture Guard
- File Safety Guard
- release metadata guard
- production release credential-free preflight
- app bundle / Sandbox baseline verification
- unsigned CI artifact
- Swift CodeQL v4
  - workflow変更PR
  - `main` default-branch source変更
  - manual dispatch
  - weekly schedule
  - first-party SwiftPM core targetをmanual build-modeで解析
- 500-item Folder Snapshot Performance Baseline
  - relevant source/test/workflow PR
  - manual dispatch
  - weekly schedule
  - filter mismatch防止marker
  - `worst < 0.5s` regression ceiling

v0.1 Release blockerではない追加候補:

- Periphery
- Main Thread Checker
- Integration / UI automation

追加解析はCI時間・false positive・無料枠・既存検査との重複を評価して個別PRで導入する。既にstrict `swift-format` / ASan / TSan / CodeQL / Snapshot Performance Baselineは導入済みなので、古い計画を根拠に二重導入しないこと。

### TASK-018 — Release Pipeline (historical Developer ID design)
Status: **HISTORICAL / INACTIVE under ADR-0011**

以下の署名・公証パイプラインは当時実装された旧設計の記録です。v0.2の現行ad-hoc公開のマージ条件や起動手順ではありません。

コード実装済み:

- strict `X.Y.Z` marketing version policy
- positive integer build number policy
- Debug / Release metadata consistency guard
- `vX.Y.Z` tag / project version validation
- unsigned Release Candidate workflow
- unsigned app version / Sandbox baseline verification
- SHA-256 artifact manifest + self-verification
- immutable bad-release / rollback policy
- ADR-0006: v0.1はDeveloper ID direct distributionを採用
- App Sandbox / Hardened Runtimeをproductionでも維持
- protected `production-release` environmentを前提にしたcredential contract
- credential-free preflight / fail-closed regression
- temporary keychainへのDeveloper ID certificate import
- Developer ID signed Release archive
- post-sign `codesign --verify --deep --strict`
- Developer ID authority / TeamIdentifier / Hardened Runtime / timestamp検証
- signed entitlements再検証
- `notarytool` submission + `Accepted`必須
- notarization ticket staple / validate
- Gatekeeper assessment
- final signed ZIP + SHA-256 manifest
- signed/notarized candidate Actions artifact
- `RELEASE_EVIDENCE.txt` schema v1
  - required keys exactly once
  - unknown / malformed key rejection
  - signed ZIP-derived bundle identifier / version / build
  - exact source commit evidence
- candidate workflow identityのfail-closed検証
  - name = `Production Release Candidate`
  - path = `.github/workflows/production-release.yml`
  - event = `workflow_dispatch`
  - branch = `main`
  - completed / success
  - valid 40-character lowercase SHA
- Manual QA後のGitHub Release promotion workflow
- candidate source SHA / evidence / checksum再検証
- candidate commitがDraft作成前とDraft asset validation後の公開直前に、それぞれfreshly fetched current `main`とexact matchすることを検証
- public Release build history gate
  - normal production Releaseは`RELEASE_EVIDENCE.txt`からbuild historyを検証
  - pre-evidence v0.1.0 / v0.1.1はpinned legacy manifest + live Release target + published `BUILD_INFO.txt` SHA-256/contentをexact validation
  - candidate `bundle_build > max(public release bundle_build)`必須
  - unknown / modified / missing / malformed historical evidenceはfail-closed
- pre-existing tag / release拒否
- asset-free Draft作成 → exact target SHA検証
- Draft asset verification
- publish後`isImmutable=true`必須
- mutable releaseを正式Releaseとして残さないcleanup path
- public ReleaseへZIP / `SHA256SUMS` / `RELEASE_EVIDENCE.txt`添付

旧Developer ID設計に残っていた運用検証（**現在のリリースブロッカーではない**）:

- `production-release` environmentへ実credentialを設定
- repository release immutabilityを有効化
- `main` branch protection / required checkなどrelease governanceを確認
- 最初のcredentialed signed/notarized candidateを成功させる
- signed candidateで`docs/MANUAL_QA.md`を完走
- current `0.2.0 / build 3` candidateをDeveloper ID signed / notarized immutable Releaseとしてpublishして検証

これらは歴史的なIssue #33で追跡していた項目です。**現行ad-hoc公開にDeveloper ID credentialや公証は不要**です。実credential値をRepositoryへcommitしない。

### TASK-019 — Documentation
Status: **DONE for current code/document baseline / production release record pending**

実装済み:

- README / implementation status同期
- Recovery UX documentation
- Release policy
- Install guidance
- signed-artifact Manual QA checklist
- production credential contract documentation
- release evidence schema / exact candidate workflow identity documentation
- public build-number history gate documentation
- snapshot performance baseline / technical-debt revisit contract
- persistent / runtime / fallback folder identity contract documentation

Release時に残る記録:

- tested candidate commit / version / build
- tested macOS versions
- CI / sanitizer / CodeQL / performance status
- signed candidate workflow run
- artifact SHA-256
- Manual QA実施記録
- final immutable Release URL / tag

---

## Current Release Next Order — ad-hoc v0.2

Current source metadata is `v0.2.0 / build 3`. The latest public release is v0.1.1 (ad-hoc, not Apple-notarized). This section supersedes the old Issue #33 / Developer ID publication sequence retained above.

1. **#519 (repository administrator):** Apply the checked-in sole canonical main ruleset and enable repository-wide Release immutability; from a clean checkout at exact live `main`, pass `Scripts/setup-release-governance.sh Lamy210/SchneeGlass --verify-only`. Record read-back evidence; do not claim that configured source files are proof of live settings.
2. **#547 (maintainer + owner):** Reconcile Draft Publisher with latest `main`, validate the new HEAD with both Bootstrap jobs and publisher fixtures, review the scoped owner token's permissions and nontransactional failure recovery, then explicitly authorize merging. **Do not publish or set credentials just because the PR tests pass.**
3. **#520 (release owner):** After final code changes, freeze exact `main`; verify both Bootstrap jobs for that SHA and generate a new manually dispatched `Ad-Hoc Release Candidate`. Keep the exact run/attempt/artifact IDs and independently checked outer/inner ZIP digests. Any further main change invalidates the candidate's exact-source binding.
4. **#520 (real macOS QA):** On macOS 15/26, verify actual app signature/entitlements, first-launch Gatekeeper UX, core Glass operations, copy-only File Safety/Recovery, restart, and upgrade from v0.1.1 using disposable folders. Record SHA/digests/OS/results; never fabricate QA or disable Gatekeeper globally.
5. **#520 (owner-only decision):** Personally post the exact unedited owner QA comment bound to the verified **inner ZIP digest**. Run authenticated read-only publication preflight, public history and tag/collision checks. Only after all live gates pass, provision the reviewed credential and explicitly dispatch the merged create-only ad-hoc publisher; verify the immutable published Release's tag, IDs and all four assets by read-back. If API writes partially succeed or the response is lost, stop for manual reconciliation; no automatic retries or destructive cleanup.

No `Production Release Candidate`, `Publish Production Release`, Apple notarization or `production-release` Environment is part of the active path. The permanent non-destructive File Safety contract remains mandatory. For details, use [RELEASE.md](../RELEASE.md), [Manual QA](MANUAL_QA.md), and [Issue #520](https://github.com/Lamy210/SchneeGlass/issues/520).

---

## 実装原則

実装順を変更する場合でも以下を破ってはいけない。

```text
Filesystem source of truth
UI -> concrete filesystem adapter 禁止
User-owned source destructive mutation 禁止
Security-scoped acquire/release balance
Unknown data auto-delete 禁止
Silent recovery rollback 禁止
Unsigned artifact production公開禁止
Mutable release artifact差し替え禁止
```

Architectureを変更する必要がある場合は、実装で先に回避せずADRを追加して判断する。
