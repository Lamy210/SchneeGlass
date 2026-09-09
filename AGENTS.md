# AGENTS.md — SchneeGlass Coding Agent Rules

このRepositoryに対するHuman / AI Coding Agentの最上位実装規約です。

## 1. Safety First

### NEVER

- UIからfilesystem mutationを行う
- user-owned sourceをMove / Rename / Delete / Replaceする
- Existing destinationをsilent overwriteする
- Full Disk Accessを要求する
- Accessibility Permissionを追加する
- Private macOS API / private CGS symbolを使用する
- Network entitlementを設計変更なしに追加する
- Dependencyを`DEPENDENCIES.md`更新なしに追加する
- Failing safety testを削除・skipしてgreenにする
- `@unchecked Sendable`でcompiler errorを黙らせる
- File Safety pathで`try?`を使いFailureを握り潰す
- Secret / Token / Credential / Private KeyをCommitする
- 実在会社・顧客・内部PathをTest Fixtureに使う

### MUST

- FilesystemをSource of Truthとする
- user-visible destinationのFile mutationを`SchneeGlassFileSystemAdapter`のallowlist内へ限定する
- SchneeGlass-owned metadataのFile mutationを`SchneeGlassPOSIXSupport.PhysicalStateStore`のallowlist内へ限定する
- Security-scoped accessのAcquire/Releaseをbalanceする
- File Safety changeと同じPRでSafety Testを追加/更新する
- Schema changeと同じPRでMigration/Recovery Testを追加する
- Architecture Decisionを変更する場合ADRを追加/更新する
- Runtime Dependency追加時に`DEPENDENCIES.md`を更新する
- Errorを明示的なDomain/User-facing Stateへmapする

## 2. Architecture Boundaries

依存方向は`ARCHITECTURE.md`に従う。

特に:

```text
Presentation -> Concrete FileSystem Adapter   禁止
Presentation -> Concrete Persistence Adapter  禁止
Presentation -> SchneeGlassPOSIXSupport        禁止
Domain -> SwiftUI/AppKit                       禁止
Domain -> SchneeGlassPOSIXSupport              禁止
FileDomain -> SchneeGlassApplication           禁止
FileDomain -> SchneeGlassPOSIXSupport           禁止
SchneeGlassPOSIXSupport -> Domain/Application/Presentation/Concrete Adapter  禁止
```

`GlassContentState`やSecurity Scope付きCopy Requestのように複数Layerを組み合わせる型は、循環依存を避けるためApplication Layerへ配置する。

Architecture BoundaryをbypassするためにSource Fileを別Targetへ移動してはいけない。

## 3. Concurrency

```text
UI mutable state       -> @MainActor
Shared mutable service -> actor
Cross-isolation value  -> Sendable value type
```

- Structured Concurrencyを優先する
- `Task.detached`は原則禁止。必要ならADR
- `@unchecked Sendable`は原則禁止。必要ならADR + Thread-safety rationale + Tests

## 4. Error Handling

Production Safety Pathでは:

```text
try!          禁止
force unwrap  原則禁止
as!           原則禁止
try?          correctnessに関わる処理では禁止
```

Raw `NSError`をそのままUIへ表示しない。

## 5. Public Repository Safety

このRepositoryはPublicです。

Commit前に必ず確認:

- Secretがない
- Credentialがない
- Local Absolute Pathがない
- Company/Internal/Customer Nameがない
- Raw Bookmark Dataがない
- Signing Private Materialがない

Sampleは架空値を使う。

CIでは以下を実行する。

```text
Scripts/verify-public-repo.sh
Scripts/verify-architecture.sh
Scripts/verify-file-safety.sh
```

Guardを回避するためのrenameやencoding変更は禁止する。

## 6. Change Discipline

基本:

```text
1 PR = 1 conceptual change
```

次を1 PRへ混在させない:

```text
architecture refactor
new feature
dependency update
large UI redesign
```

やむを得ない場合はPR Bodyで理由を説明する。

## 7. Xcode Project Policy

未検証の`project.pbxproj`を手書き生成してCommitしない。

Xcode App Targetは実際のXcode環境で生成し、最低限以下を確認してからCommitする。

```text
Debug build PASS
Release build PASS
Local SchneeGlassKit linkage PASS
Entitlement linkage PASS
```

AIが推測だけでpbxprojのobjectVersionやBuild Settingを作成してはいけない。

## 8. TODO / Tech Debt

Bare `TODO` / `FIXME`をSwift Sourceへ追加しない。

```text
TODO(#123)
FIXME(#123)
```

の形式とし、Intentional Debtは`TECH_DEBT.md`またはIssueに理由とRevisit Triggerを記録する。

## 9. Definition of Done

Feature完了は「動く」だけではない。

- Implementation
- Success Path Test
- Failure Path Test
- Recovery Behavior
- Accessibility Impact
- Logging/Privacy Check
- Architecture Gate
- Documentation Update when needed

File Operation変更の場合はFileSafety Suite PASSが必須。
SchneeGlass-owned metadata storage変更の場合はphysical topology regression test PASSが必須。
