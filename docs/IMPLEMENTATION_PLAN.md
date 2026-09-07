# SchneeGlass v0.1 Implementation Plan

このドキュメントは `ARCHITECTURE.md` の設計を実装順へ落としたものです。

## Phase 0 — Architecture Baseline

### TASK-000 — 設計Baseline

Status: **DONE on `bootstrap/architecture-baseline`**

- Architecture
- Security
- Testing
- Dependency policy
- Agent rules
- Tech debt policy
- ADR baseline

---

## Phase 1 — Bootstrap

### TASK-001 — Project / Package Bootstrap

Status: **IN PROGRESS**

完了済み:

- `Packages/SchneeGlassKit/Package.swift`
- macOS 15 platform declaration
- Swift 6 language mode
- SPM architecture targets
- App Sandbox entitlement baseline
- Domain/Application contract skeleton
- Initial Swift Testing tests
- Architecture guard
- File mutation allowlist guard
- Public repository guard
- Bootstrap GitHub Actions CI

未完了:

- Xcode macOS App target
- Local package linkage from App target
- `CODE_SIGN_ENTITLEMENTS` linkage
- App target Debug/Release build verification

Xcode Projectは、使用可能なXcode環境で生成・検証してからCommitする。
未検証の`project.pbxproj`を手書きでCommitしない。

Completion Criteria:

```text
SPM tests PASS
Architecture guard PASS
File safety guard PASS
Public repo guard PASS
App target Debug build PASS
App target Release build PASS
```

---

## Phase 2 — Core Domain / Application

### TASK-002 — Domain Contracts

Status: **STARTED**

初期実装済み:

- `GlassID`
- `ResourceFingerprint`
- `FolderSource`
- `GlassPlacement`
- `GlassConfiguration`
- `FileIdentity`
- `FolderIdentity`
- `FileKind`
- `GlassItem`
- `FolderSnapshot`
- `StorageCapabilities`
- `DropCandidate`
- `DestinationDescriptor`
- `CopyItemPlan`
- `CopyBatchPlan`
- `DropPlan`
- `DropRejection`

残り:

- File classification implementation
- DropPlanner
- Production-level error mapping
- Additional invariant tests

### TASK-003 — Application Ports / Use Cases

Status: **STARTED**

初期Contract済み:

- `FolderAccessHandle`
- `AuthorizedCopyBatchRequest`
- `CopyBatchResult`
- `CopyProgress`
- `GlassContentState`
- `InteractionState`
- Application Ports

残り:

- Use Case implementation
- Runtime session orchestration
- Fake ports for application tests

---

## Phase 3 — macOS / Filesystem Adapters

### TASK-004 — Security Scoped Access
Status: NOT STARTED

### TASK-005 — Folder Snapshot Reader
Status: NOT STARTED

### TASK-006 — File Event Hub
Status: NOT STARTED

### TASK-007 — Drop Planner
Status: NOT STARTED

### TASK-008 — Recovery Metadata Store
Status: NOT STARTED

### TASK-009 — Safe File Copy Engine
Status: NOT STARTED

---

## Phase 4 — Persistence / Recovery

### TASK-010 — Configuration Store
Status: NOT STARTED

### TASK-011 — Startup / Recovery Coordinator
Status: NOT STARTED

---

## Phase 5 — macOS UI

### TASK-012 — Windowing
Status: NOT STARTED

### TASK-013 — Glass Presentation
Status: NOT STARTED

### TASK-014 — Open / Finder Integration
Status: NOT STARTED

### TASK-015 — Menu Bar / Global Shortcut
Status: NOT STARTED

---

## Phase 6 — Quality / Release

### TASK-016 — Static Architecture / Safety Gates

Status: **BASELINE DONE**

実装追加に合わせてallowlistと検査項目を拡張する。

### TASK-017 — CI / Diagnostics

Status: **BOOTSTRAP CI DONE / FULL CI NOT STARTED**

追加予定:

- swift-format
- SwiftLint
- Periphery
- CodeQL
- ASan
- TSan
- Main Thread Checker
- Integration test plan

### TASK-018 — Release Pipeline
Status: NOT STARTED

### TASK-019 — Documentation
Status: IN PROGRESS

---

## 実装原則

実装順を変更する場合でも以下を破ってはいけない。

```text
Filesystem source of truth
UI -> concrete filesystem adapter 禁止
User-owned source destructive mutation 禁止
Security-scoped acquire/release balance
Unknown data auto-delete 禁止
```

Architectureを変更する必要がある場合は、実装で先に回避せずADRを追加して判断する。
