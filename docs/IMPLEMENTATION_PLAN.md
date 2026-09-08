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
- resource replacement detection
- failure cleanup

### TASK-005 — Folder Snapshot Reader
Status: **DONE**

- direct-child only
- hidden item filtering
- 500-item display limit
- symlink / alias / package / directory / regular classification

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
  - fingerprint identity validation
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

Status: **IN PROGRESS**

現在のCI:

- macOS 26 / Xcode 26.6 toolchain verification
- Swift Package tests
- pull request時のAddressSanitizer package tests
- Debug app build
- Release app build
- macOS 15 compatibility package tests / app build
- Public Repository Guard
- Architecture Guard
- File Safety Guard
- app bundle / Sandbox baseline verification
- unsigned CI artifact

追加候補:

- formatting / lint gate
- Periphery
- CodeQL
- TSan
- Main Thread Checker
- Integration / UI test plan

Sanitizerや追加解析はCI時間・false positive・無料枠を評価して個別PRで導入する。AddressSanitizerは通常package testと同じcanonical runner上でPR時のみ実行し、追加runner起動を避ける。

### TASK-018 — Release Pipeline
Status: **NOT STARTED**

残り:

- versioning policy
- signed archive
- Developer ID / App Store distribution strategy
- notarization
- release artifact integrity
- credential injection through secret store
- rollback / bad release handling

### TASK-019 — Documentation
Status: **IN PROGRESS**

- README / implementation status同期
- Recovery UX documentation
- release / install documentation
- manual QA checklist

---

## v0.1 Next Order

現時点の優先順位:

```text
1. Quality / Diagnostics gap review
2. Release Pipeline
3. Final docs + manual QA
```

Recoveryのv0.1必須導線は完了。以後も最優先原則は、障害時を含めuser-owned fileを自動破壊しないこと。

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
```

Architectureを変更する必要がある場合は、実装で先に回避せずADRを追加して判断する。
