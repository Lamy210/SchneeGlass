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

Domain / Application / Adapterのcritical contractをpackage testsで固定し、real-filesystem testsはUUIDごとのisolated temporary rootを使用します。

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

- Domain → SwiftUI/AppKit/CoreServices/GRDB import
- Presentation → FileSystem/Persistence Concrete Adapter import
- Private CGS symbol
- 無承認`@unchecked Sendable`
- Swift source内のIssue番号なしTODO/FIXME

### File Safety Guard

`removeItem` / `moveItem` / `replaceItem` 相当APIの利用場所をallowlist方式で検査します。

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

---

## 6. Fault Injection

FakeだけでSafetyを証明しません。

Fault injectionとFoundation/FileManager/NSFileCoordinatorを使用したreal-filesystem testsを併用します。

対象fault例:

```text
permissionDenied
sourceMissing
destinationMissing
diskFull(afterBytes:)
commitCollision
cancelled
unexpectedIO
```

---

## 7. Recovery Tests

対象:

```text
config corruption
backup rotation
all backups corrupt
stale bookmark
bookmark failure
security-scope lifecycle
offscreen window
pending copy metadata
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

---

## 8. FSEvents Tests

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
Swift Package Tests
AddressSanitizer Package Tests
Xcode project validation
Debug app build
Release app build
Sandbox / bundle baseline
Unsigned CI artifact
```

別jobでmacOS 15 compatibility package tests / app buildも実行します。

### Scheduled / Manual — ThreadSanitizer

```text
macOS 26 / Xcode 26.6
Swift Package Tests + ThreadSanitizer
```

通常のコードPRでは追加runnerを起動せず、workflow自身の変更PR・manual dispatch・weekly scheduleで検証します。

### Release Candidate Validation

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

### Remaining diagnostics candidates

```text
formatting / lint
Periphery
CodeQL
Main Thread Checker
Integration / UI automation
Performance baseline
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
- Sandbox / signing / notarization gate failure
- supported baselineでのlaunch failure

Production releaseではDeveloper ID signing、notarization、stapling、Gatekeeper assessment、final SHA-256 manifest、Manual QAをすべて通過させます。
