# SchneeGlass

SchneeGlass は、任意の実フォルダを macOS デスクトップ上に軽量な「Glass」として配置し、Finder を開かずにファイルへアクセスできるネイティブ macOS アプリを目指すプロジェクトです。

> **Open. Local. Reversible.**
>
> SchneeGlass はユーザーのファイルを所有しません。Filesystem を Source of Truth とし、アプリを削除しても通常の Finder から同じファイルを使い続けられることを最重要原則とします。

## 現在のステータス

**v0.1 設計・Bootstrap 段階**です。現時点では production-ready なバイナリは提供していません。

v0.1 は意図的に non-destructive とし、regular file の **Copy のみ**を対象にします。

### v0.1 で行わないこと

- ユーザー所有ファイルの Move / Rename / Delete / Replace
- 既存ファイルへの暗黙的 Overwrite
- Folder の再帰 Copy
- Network destination への Write
- Runtime AI / Cloud backend
- Full Disk Access / Accessibility permission の要求
- Private macOS API の利用

## 技術方針

- Native macOS
- Swift 6 language mode
- SwiftUI + AppKit hybrid
- App Sandbox
- Security-Scoped Bookmark
- FSEvents
- NSFileCoordinator
- Swift Concurrency / Actor isolation
- Swift Package Manager only

Runtime の外部依存は原則最小化し、v0.1 では `KeyboardShortcuts` と `swift-async-algorithms` のみを初期候補とします。

## ドキュメント

- [Architecture](ARCHITECTURE.md)
- [Testing](TESTING.md)
- [Security](SECURITY.md)
- [Dependencies](DEPENDENCIES.md)
- [Technical Debt](TECH_DEBT.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)
- [ADR](docs/adr/)

## 最重要 Invariants

1. Filesystem is the source of truth.
2. UI never mutates the filesystem.
3. v0.1 ではユーザー所有ファイルを Move / Rename / Delete / Replace しない。
4. 既存 destination を暗黙的に上書きしない。
5. Security-scoped access は必ず balanced release する。
6. Unknown file / partial file を自動削除しない。
7. Recovery は後付けではなく正式な product feature とする。
8. AI 生成コードと人間が書いたコードに同じ quality gate を適用する。

## Public Repository Policy

このリポジトリは Public です。API key、token、certificate、private key、個人や勤務先に紐づく path、実在顧客情報などをコミットしないでください。詳細は [SECURITY.md](SECURITY.md) と [AGENTS.md](AGENTS.md) を参照してください。

## License

ライセンスは正式決定後に追加します。ライセンス未設定の間は、第三者が自由に利用・再配布できる OSS ライセンスが付与されているとはみなさないでください。
