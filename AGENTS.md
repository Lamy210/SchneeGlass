# AGENTS.md — SchneeGlass Coding Agent Rules

この Repository に対する Human / AI Coding Agent の最上位実装規約です。

## 1. Safety First

### NEVER

- UI から filesystem mutation を行う
- user-owned source を Move / Rename / Delete / Replace する
- Existing destination を silent overwrite する
- Full Disk Access を要求する
- Accessibility permission を追加する
- Private macOS API / private CGS symbol を使用する
- Network entitlement を設計変更なしに追加する
- Dependency を `DEPENDENCIES.md` 更新なしに追加する
- Failing safety test を削除・skipして green にする
- `@unchecked Sendable` で compiler error を黙らせる
- File Safety path で `try?` を使い failure を握り潰す
- Secret / token / credential / private key を commit する
- 実在会社・顧客・内部 path を test fixture に使う

### MUST

- Filesystem を Source of Truth とする
- File mutation を `SchneeGlassFileSystemAdapter` の allowlist 内へ限定する
- Security-scoped access の acquire/release を balance する
- File Safety change と同じ PR で safety test を追加/更新する
- Schema change と同じ PR で migration/recovery test を追加する
- Architecture decision を変更する場合 ADR を追加/更新する
- Runtime dependency 追加時に `DEPENDENCIES.md` を更新する
- Error を明示的な domain/user-facing state へ map する

## 2. Architecture Boundaries

依存方向は `ARCHITECTURE.md` に従います。

特に:

```text
Presentation -> concrete FileSystem Adapter  禁止
Presentation -> concrete Persistence Adapter 禁止
Domain -> SwiftUI/AppKit                     禁止
```

Architecture boundary を bypass するために source file を別 target へ移動してはいけません。

## 3. Concurrency

- UI mutable state → `@MainActor`
- Shared mutable service → `actor`
- Cross-isolation value → `Sendable` value type
- Structured concurrency を優先
- `Task.detached` は原則禁止。必要なら ADR
- `@unchecked Sendable` は原則禁止。必要なら ADR + thread-safety rationale + tests

## 4. Error Handling

Production safety path では:

```text
try!  禁止
force unwrap 原則禁止
as!   原則禁止
try?  correctness に関わる処理では禁止
```

Raw `NSError` をそのまま UI に表示しません。

## 5. Public Repository Safety

この Repository は Public です。

Commit 前に必ず確認:

- secret がない
- credential がない
- local absolute path がない
- company/internal/customer name がない
- raw bookmark data がない
- signing private material がない

Sample は架空値を使います。

## 6. Change Discipline

1 PR = 1 conceptual change を基本とします。

次を1 PRに混在させない:

```text
architecture refactor
new feature
dependency update
large UI redesign
```

やむを得ない場合は PR body で理由を説明します。

## 7. TODO / Tech Debt

Bare `TODO` / `FIXME` を追加しません。

```text
TODO(#123)
FIXME(#123)
```

の形式とし、intentional debt は `TECH_DEBT.md` または Issue に理由と revisit trigger を記録します。

## 8. Definition of Done

Feature 完了は「動く」だけではありません。

- implementation
- success path test
- failure path test
- recovery behavior
- accessibility impact
- logging/privacy check
- architecture gate
- documentation update when needed

File operation change の場合は FileSafety suite PASS が必須です。
