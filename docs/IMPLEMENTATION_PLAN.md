# SchneeGlass v0.1 Implementation Plan

このドキュメントは `ARCHITECTURE.md` の設計を実装順へ落としたものです。

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

- formatting / lint gate
- Periphery
- Main Thread Checker
- Integration / UI automation

追加解析はCI時間・false positive・無料枠・既存検査との重複を評価して個別PRで導入する。既にASan / TSan / CodeQL / Snapshot Performance Baselineは導入済みなので、古い計画を根拠に二重導入しないこと。

### TASK-018 — Release Pipeline
Status: **CODE COMPLETE / OPERATIONAL VALIDATION PENDING**

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
- candidate commitがcurrent `main`のancestorであることを検証
- public Release build history gate
  - first Releaseはhistory 0件でPASS
  - 2回目以降は`candidate bundle_build > max(public release bundle_build)`必須
  - missing/malformed historical evidenceはfail-closed
- pre-existing tag / release拒否
- asset-free Draft作成 → exact target SHA検証
- Draft asset verification
- publish後`isImmutable=true`必須
- mutable releaseを正式Releaseとして残さないcleanup path
- public ReleaseへZIP / `SHA256SUMS` / `RELEASE_EVIDENCE.txt`添付

残るRelease blockerはコード実装ではなく運用検証:

- `production-release` environmentへ実credentialを設定
- repository release immutabilityを有効化
- `main` branch protection / required checkなどrelease governanceを確認
- 最初のcredentialed signed/notarized candidateを成功させる
- signed candidateで`docs/MANUAL_QA.md`を完走
- 最初のimmutable v0.1 Releaseをpublishして検証

これらはIssue #33で追跡する。実credential値をRepositoryへcommitしない。

### TASK-019 — Documentation
Status: **DONE for v0.1 code/document baseline / release record pending**

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

## v0.1 Next Order

現時点の優先順位:

```text
1. Issue #33: production-release credential / governance setup
2. First credentialed Developer ID + notarized candidate
3. Signed candidate Manual QA
4. First immutable v0.1 GitHub Release publication
5. Release recordをDocumentationへ反映
```

Core / Recovery / v0.1 automated quality / release automation codeは完了。以後も最優先原則は、障害時を含めuser-owned fileを自動破壊しないこと。

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
