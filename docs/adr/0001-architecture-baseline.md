# ADR-0001: Architecture Baseline

- Status: Accepted
- Scope: v0.1

## Context

SchneeGlass はローカル filesystem と macOS windowing を扱うため、単純な MVVM のみでは View/ViewModel に platform I/O が集中するリスクがある。一方、完全な Clean Architecture/TCA/Plugin framework は初期 MVP には過剰である。

## Decision

次を採用する。

```text
Modular Monolith
+ Ports & Adapters
+ Unidirectional Presentation Flow
+ Explicit State Machines
+ Compile-time SPM Target Boundaries
```

## Consequences

Positive:

- Domain と macOS API を分離できる
- File Safety boundary を Compiler/CI で強制しやすい
- Test adapter / fault injection を導入しやすい
- v0.1 の実装量を抑えられる

Negative:

- Target dependency graph の管理が必要
- Composition Root が必要

## Rejected

- Pure MVVM only
- TCA for v0.1
- Full Clean Architecture ceremony
- Runtime Service Locator
- Plugin framework
