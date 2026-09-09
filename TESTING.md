# SchneeGlass Testing Strategy

SchneeGlass はファイルを扱うため、テストを「実装後の確認」ではなく Architecture の一部として扱います。

## 1. 最優先Invariant

```text
Source file loss = 0
Silent overwrite = 0
User-owned Move/Rename/Delete = 0
Unknown partial auto-delete = 0
Security scope leak = 0
UI -> concrete filesystem mutation adapter = 0
Owned metadata symlink traversal = 0
```

Coverage率だけではRelease可否を決めません。

Critical scenario coverageを優先します。

---

## 2. Test Categories

```text
Unit
Architecture
FileSafety
Recovery
Integration
Snapshot
UI
Performance
ReleaseArtifact
ManualQA
```

Priority:

```text
FileSafety
>
Recovery
>
Architecture
>
Domain
>
Integration
>
UI
```

---

## 3. Swift Package Tests

`Packages/SchneeGlassKit` に対してSwift Testingを使用します。

Domain / Application / Adapter / shared infrastructureのcritical contractをpackage testsで固定し、real-filesystem testsはUUIDごとのisolated temporary rootを使用します。

通常実行:

```bash
swift test --package-path Packages/SchneeGlassKit
```

AddressSanitizer:

```bash
swift test \
  --package-path Packages/SchneeGlassKit \
  --sanitize=address
```

ThreadSanitizer:

```bash
swift test \
  --package-path Packages/SchneeGlassKit \
  --sanitize=thread
```

---

## 4. CI Safety Guards

Bootstrap CIでは次を必須とします。

```text
Scripts/verify-public-repo.sh
Scripts/verify-architecture.sh
Scripts/verify-file-safety.sh
Scripts/verify-release-metadata.sh
Scripts/verify-production-release-preflight.sh
swift test --package-path Packages/SchneeGlassKit
```

### Public Repository Guard

検出対象:

- credential-like tracked file
- private-key marker
- high-confidence GitHub token pattern

これはGitHub Secret Scanning等を置き換えるものではなく、Repository内の第一防衛線です。

### Architecture Guard

検出対象:

- Domain → SwiftUI/AppKit/CoreServices/GRDB/`SchneeGlassPOSIXSupport` import
- Presentation → FileSystem/Persistence Concrete Adapter / `SchneeGlassPOSIXSupport` import
- `SchneeGlassPOSIXSupport` → Domain/Application/Presentation/Concrete Adapter import
- Private CGS symbol
- 無承認`@unchecked Sendable`
- Swift source内のIssue番号なしTODO/FIXME

### File Safety Guard

user-visible mutationの`removeItem` / `moveItem` / `replaceItem`、source-copy authorityの`fcopyfile` / `O_CREAT`、owned metadata mutationの`mkdirat` / `renameat` / `unlinkat` / `O_CREAT`相当APIをallowlist方式で検査します。

user-visible destination mutationは`SchneeGlassFileSystemAdapter`、SchneeGlass-owned metadata mutationは`SchneeGlassPOSIXSupport.PhysicalStateStore`へ限定します。

新しいmutation APIやallowlist対象を追加する場合は、同一PRでSafety rationaleと実Filesystem testを追加します。

---

## 5. FileSafety Tests

実Filesystem用Test root:

```text
/tmp/SchneeGlassTests/<UUID>/
├ source/
├ destination/
└ unrelated/
```

各Testは独立したUUID rootを使用します。

実ユーザーFolderや会社FolderをFixtureに使用してはいけません。

主要Case:

- normal regular-file copy
- collision
- same-directory no-op
- folder/package/symlink reject
- multi-file preflight failure
- disk full / I/O fault injection
- source disappears
- destination disappears
- commit collision race
- partial recovery
- unknown `.glass-*` safety
- ownership identity mismatch
- final user-visible file non-deletion
- app-owned root symlink rejection
- app-owned descendant directory symlink rejection
- app-owned metadata leaf symlink/non-regular rejection
- physical regular-file listing/removal
- atomic owned-state round trip

---

## 6. Fault Injection

FakeだけでSafetyを証明しません。

Fault injectionとFoundation/FileManager/NSFileCoordinator/POSIX primitiveを使用したreal-filesystem testsを併用します。

対象fault例:

```text
permissionDenied
sourceMissing
destinationMissing
diskFull(afterBytes:)
commitCollision
cancelled
unexpectedIO
unsafeOwnedStateTopology
```

---

## 7. Recovery Tests

対象:

```text
config corruption
backup rotation
all backups corrupt
unsafe configuration topology
stale bookmark
bookmark failure
security-scope lifecycle
offscreen window
pending copy metadata
unsafe pending-copy metadata topology
ambiguous partial
ownership mismatch
stale recovery action
destination reconnect mismatch
```

Recovery testでは次を特に固定します。

- stale UI assessmentをmutation authorityにしない
- ownership proofなしのstagingを削除しない
- final user-visible fileを自動削除しない
- Copy / Recovery mutationを同時実行しない
- configuration restoreの結果と返却結果を一致させる
- app-owned metadataのsymlink targetをread/writeしない
- unsafe owned-state topologyではcurrent stateを変更せずfail-closedする

---

## 8. FSEvents / Snapshot Tests

Event件数をassertしません。

検証対象は最終observable stateです。

```text
Filesystem change
↓
eventually
↓
FolderSnapshot == final filesystem state
```

Startup snapshot中のeventを取りこぼさないこともcritical contractです。

### 500-item Snapshot Performance Baseline

DEBT-001のRevisit Triggerを実測可能にするため、`NativeFolderSnapshotReader`の500-item direct-child snapshotを専用workflowで測定します。

Test contract:

```text
501 direct-child files
↓
500 items returned + isTruncated == true
↓
3 snapshots
↓
ProcessInfo.systemUptimeで測定
↓
worst < 0.5s
```

通常package test / ASanでは`SCHNEEGLASS_PERFORMANCE_BASELINE`未設定のためperformance measurementはskipします。専用workflowだけが`SCHNEEGLASS_PERFORMANCE_BASELINE=1`を設定します。

CI logには必ず次のmarkerを出し、filter mismatch等で0 testのままgreenになることを防ぎます。

```text
SCHNEEGLASS_PERF_RESULT snapshot_500 ...
```

PR #39導入時の最終GitHub-hosted macOS 26 / Xcode 26.6実測:

```text
average = 0.055926s
worst   = 0.059213s
limit   = 0.500000s
```

単発のshared-runner jitterだけで設計変更を判断せず、継続超過または実機UI responsivenessへの影響をRevisit Triggerとします。

---

## 9. Test-only Dependencies

Runtime BinaryへTest dependencyを持ち込みません。

新規test dependencyは、標準library / Foundationだけでは表現しにくいtest capabilityに限定し、追加理由とtransitive dependencyを同一PRで確認します。

---

## 10. Current CI Matrix

### Pull Request — Bootstrap CI

```text
Xcode 26.6 toolchain guard
Public Repository Guard
Architecture Guard
File Safety Guard
Release Metadata Guard
Production release credential-free preflight
Swift Package Tests
AddressSanitizer Package Tests
Xcode project validation
Debug app build
Release app build
Sandbox / bundle baseline
Unsigned CI artifact
```

別jobでmacOS 15 compatibility package tests / app buildも実行します。

### Relevant PR / Scheduled / Manual — Snapshot Performance Baseline

`.github/workflows/snapshot-performance.yml`:

```text
macOS 26 / Xcode 26.6
500-item direct-child snapshot
3-run monotonic-clock measurement
worst < 0.5s
performance marker required
```

実行条件:

- workflow自身変更PR
- `NativeFolderSnapshotReader.swift`変更PR
- 対応test変更PR
- manual dispatch
- weekly schedule

無関係PRでは追加macOS runnerを起動しません。

### Scheduled / Manual — ThreadSanitizer

```text
macOS 26 / Xcode 26.6
Swift Package Tests + ThreadSanitizer
```

通常のコードPRでは追加runnerを起動せず、workflow自身の変更PR・manual dispatch・weekly scheduleで検証します。

### Scheduled / Manual / Default Branch — Swift CodeQL

```text
macOS 26 / Xcode 26.6
github/codeql-action v4
language = swift
build-mode = manual
first-party SwiftPM core targets
SARIF upload
```

CodeQLはSwiftでbuild-mode `none`を使用せず、first-party coreを明示buildして解析します。第三者`KeyboardShortcuts`を含む`SchneeGlassMacOSAdapter`はCodeQL tracing対象から外し、通常Bootstrap CI / package tests / sanitizerでコンパイル検証します。

実行条件:

- CodeQL workflow自身を変更するPR
- `main`上のSchneeGlassKit source / Package.swift変更
- manual dispatch
- weekly schedule

### Unsigned Release Candidate Validation

release関連PR、manual dispatch、`v*.*.*` tagで次を検証します。

```text
Release metadata / tag consistency
Swift Package Tests
Unsigned Release build
Bundle version / Sandbox baseline
ZIP packaging
SHA-256 manifest
SHA-256 self verification
Artifact upload
```

unsigned artifactはproduction releaseではありません。

### Production Release Candidate

`main`からのmanual dispatch + explicit confirmation + protected `production-release` environmentに限定します。

Credential-free pathでは次をCIで固定します。

```text
production release preflight
signing/evidence helper shell syntax
credential不足でfail-closed
credential-free失敗時にrelease-outputを生成しない
schema v1 evidence fixture
unknown evidence key rejection
PRでは実signing jobをskip
```

実credentialを設定したproduction jobでは次をすべてPASSさせます。

```text
Developer ID temporary keychain import
exact Developer ID identity / Team ID match
signed Release archive
codesign --verify --deep --strict
Hardened Runtime / secure timestamp
signed entitlements
notarytool Accepted
stapler staple / validate
Gatekeeper assessment
final SHA-256 manifest
signed/notarized candidate artifact
schema v1 RELEASE_EVIDENCE.txt
signed ZIP-derived bundle identifier / version / build
exact source commit evidence
complete evidence validation before artifact upload
```

### Production Release Publication

Signed/notarized candidateを直接自動公開しません。Manual QA完了後、`Publish Production Release`を`main`から手動実行します。

Publication jobは以下を再検証します。

```text
candidate workflow name == Production Release Candidate
candidate workflow path == .github/workflows/production-release.yml
event == workflow_dispatch
branch == main
status == completed / conclusion == success
valid candidate source commit SHA
schema v1 release evidence
unknown/malformed evidence rejection
bundle identifier / version / positive build
notarization / codesign / stapler / Gatekeeper state
evidence commit SHA == candidate workflow head SHA
SHA256SUMS
candidate commit is ancestor of current main
public Release build-number history
pre-existing tag / release absence
draft target SHA / assets
published release isImmutable == true
```

Build history contract:

```text
public Release 0件:
  first releaseとしてPASS

public Release 1件以上:
  candidate bundle_build > max(all public release bundle_build)
```

過去public Releaseの`RELEASE_EVIDENCE.txt`が取得不能・malformed・unsupported schemaの場合は公開せずfail-closedします。prereleaseもnon-draftならdistribution historyとして扱います。

公開Releaseには少なくとも次を添付します。

```text
SchneeGlass-X.Y.Z.zip
SHA256SUMS
RELEASE_EVIDENCE.txt
```

mutable releaseを正式Releaseとして残してはいけません。

### Additional diagnostics candidates

以下はv0.1の現行Release blockerではありません。

```text
formatting / lint
Periphery
Main Thread Checker
Integration / UI automation
```

追加解析はCI時間・false positive・無料枠・既存検査との重複を評価し、個別PRで導入します。

---

## 11. Manual QA

CIでは完全に代替できない実ユーザー操作とartifact確認は [`docs/MANUAL_QA.md`](docs/MANUAL_QA.md) をRelease gateとして使用します。

最低でも以下を人手確認します。

- clean install / first launch
- Create Glass / persistence
- filesystem source-of-truth
- copy-only / no overwrite
- Pending Copy Recovery
- destination reconnect
- configuration backup recovery
- multi-display / offscreen recovery
- Menu Bar / Global Shortcut
- supported macOS baseline
- signed production candidateのcodesign / notarization / stapling / Gatekeeper
- quarantine付き配布相当artifactからのlaunch
- exact candidate workflow path / source SHA / schema v1 evidence
- build-number history gate

Manual QAが自動Safety testの代替になることも、自動testがManual QAの代替になることもありません。

---

## 12. Release原則

Safety TestをskipしてGreenにすることは禁止します。

Snapshotの1px差よりFile Safety failureを重大として扱います。

Source codeだけでなく、最終的にユーザーがDownloadするRelease Artifactまで検証します。

Release blockerの代表例:

- source file loss / silent overwrite
- user-owned Move/Rename/Delete
- ownership proofなしのRecovery deletion
- stale stateをauthorityにしたmutation
- owned metadata symlink traversal / unsafe topology mutation
- Sandbox / signing / notarization gate failure
- supported baselineでのlaunch failure
- mutable production release
- candidate workflow identity / source / evidence / checksum不一致
- release evidence schema violation
- reused / decreasing public build number
- public build historyを証明できない状態

Production releaseではDeveloper ID signing、notarization、stapling、Gatekeeper assessment、final SHA-256 manifest、Manual QA、exact candidate provenance validation、monotonic build history、immutable publicationをすべて通過させます。
