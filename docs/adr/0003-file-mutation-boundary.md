# ADR-0003: File Mutation Security Boundary

- Status: Accepted
- Scope: v0.1+

## Context

SchneeGlass は AI-assisted development を前提としており、UI や feature code から `FileManager` mutation API が偶発的に呼ばれる設計は受け入れられない。

## Decision

Filesystem mutation は `SchneeGlassFileSystemAdapter` の allowlisted implementation に限定する。

ユーザー所有 source は Move / Rename / Delete / Replace しない。

唯一の内部例外として、現在の operation が作成し recovery metadata を持つ staging file を同一 destination directory 内で final name へ commit する rename を許可する。

実装責務:

```text
SafeFileCopyEngine
InternalStagingCommitter
```

Presentation/Application/Domain から Concrete mutation adapter への直接依存を禁止する。

## Enforcement

CI で次を検査する。

- Mutation API 使用箇所 allowlist
- Presentation の concrete adapter import
- Domain の AppKit/SwiftUI import

## Consequences

安全性が上がる一方、filesystem operation の追加時は明示的に boundary と test を拡張する必要がある。
