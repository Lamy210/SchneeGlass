# Dependency Policy

SchneeGlassはRuntime dependencyを最小化します。

優先順位:

```text
Apple Platform API
→ Swift official package
→ mature third-party OSS
```

## 1. Runtime Dependencies

### KeyboardShortcuts 2.4.0

用途:

- User-customizable Global Show/Hide Shortcut
- Shortcut recorder UI
- Sandbox-compatible global hotkey registration

導入対象:

```text
SchneeGlassMacOSAdapter only
```

Domain / Application / Presentationへ`KeyboardShortcuts`型を漏らしません。

Pin:

```text
exact 2.4.0
revision 1aef85578fdd4f9eaeeb8d53b7b4fc31bf08fe27
```

採用タイミング:

`TASK-015 Menu Bar / Global Shortcut`

採用理由:

- macOS global shortcutとconflict-aware recorder UIを自前実装する価値が低い
- Sandbox / Mac App Store compatible
- Swift Package Manager対応
- `swift-tools-version: 6.1`で、SchneeGlassのmacOS 15 compatibility runner（Xcode 16.4 / Swift 6.1.2）と互換
- 2.x系最新の2.4.0は`removeHandler()`を備え、lifecycle cleanupを明示できる
- transitive package dependencyなし
- MIT License

3.xを採用しない理由:

- KeyboardShortcuts 3.0.0以降は`swift-tools-version: 6.2`
- SchneeGlassはmacOS 15 compatibility CIでSwift 6.1.2を継続検証するため、現時点では解決不能
- compatibility baselineを上げるまでは2.4.0を維持する

Security / Privacy:

- Accessibility Permissionを要求しない
- Full Disk Accessを要求しない
- Network entitlementを追加しない
- user keyboard input全体を監視するglobal event monitorは使用しない
- 登録済みshortcut eventだけを扱う

Removal Strategy:

- `SchneeGlassMacOSAdapter`のshortcut adapterとsettings recorderを削除
- `Package.swift`のproduct/package dependencyを削除
- `Package.resolved` pinを削除

## 2. v0.1 Runtime Candidates

### swift-async-algorithms

用途:

- FSEvents等のAsyncSequence debounce / event composition

初期Pin候補:

```text
1.1.5
```

採用タイミング:

`TASK-006 File Event Hub`

Apple/Swift標準APIだけで同等の簡潔性・検証容易性が得られる場合は導入しない。

## 3. Test-only Candidates

### SnapshotTesting

用途:

- SwiftUI visual regression

Runtime Binaryへ持ち込まない。

### swift-clocks

用途:

- debounce
- progress delay
- toast duration
- retry timing

のdeterministic test。

Runtime/Application Coreへ直接第三者Clock型を漏らすかどうかは導入時にADRまたはDependency Reviewで確認する。

## 4. Future Runtime Candidates

### GRDB

v0.2 Safe Move / Undo / Operation Journal導入時に再評価する。

v0.1では不要。

### Sparkle

v0.1.1以降のDirect Distribution Updateで再評価する。

v0.1 BootstrapではNetwork Entitlementを持たないため導入しない。

## 5. Dependency Admission Checklist

追加にはすべて必要:

```text
Apple APIでは不足している
Active Maintenance
Swift 6 Compatible
SPM Support
License Acceptable
Transitive Dependenciesを把握
Security Sensitive Pathへの影響を確認
Removal Strategyあり
DEPENDENCIES.md更新
CI PASS
```

## 6. Locking / Update

External Dependency導入後は`Package.resolved`をCommitする。

Dependency PRのAuto Mergeは禁止する。

Dependency追加・Major Updateは通常Feature変更と分離したPRで行う。
