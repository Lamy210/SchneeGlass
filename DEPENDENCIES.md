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

## 3. Test-only Dependencies

### SnapshotTesting 1.19.4

用途:

- macOS SwiftUI visual regression
- Pull Request上でDesktop Glassのvisual state差分をPNGとして確認する

導入対象:

```text
SchneeGlassVisualSnapshotTests only
```

Runtime Binaryへ持ち込まず、Production targetから`SnapshotTesting`型を参照しません。

Pin:

```text
exact 1.19.4
revision 59a99c458de4d2dee580529b61b4f78dca7b7fa6
```

採用理由:

- SwiftUI/AppKitのpixel snapshotとdiffを自前実装する価値が低い
- macOS `NSView` image snapshotを標準strategyとして提供する
- Swift Testing integrationを持つ
- SPM対応
- MIT License
- 1.19.4は2026-07-28時点のlatest stable release

CI Policy:

- Visual snapshot verificationはcanonical macOS 26 / Xcode 26.6のみで実行する
- macOS 15 compatibility jobでは画像比較しない
- CIは`SNAPSHOT_TESTING_RECORD=never`でreference imageを更新しない
- reference image更新は`Scripts/update-visual-snapshots.sh`から明示的に実行する
- OS / SwiftUI / AppKit / SF Symbols差を製品UI regressionと誤認しないため、referenceはcanonical toolchain単位で管理する

Resolved Package Graph:

`SnapshotTesting` product自体は追加package productをlinkしませんが、upstream package manifestがoptional sibling products用dependencyを宣言するため、SwiftPM resolverは次もlockします。

```text
swift-custom-dump 1.3.3
swift-syntax 603.0.0
xctest-dynamic-overlay 1.6.1
```

`swift-custom-dump`は互換runnerで解決可能な1.3.3をlockします。新しいreleaseへ無条件更新するとSwift tools baselineが上がり、macOS 15 / Xcode 16.4 compatibility resolutionを壊す可能性があるため、SnapshotTesting更新時にgraph全体を再検証します。

Security / Privacy:

- Network entitlementを追加しない
- App Sandbox entitlementを変更しない
- snapshot fixtureへ実ユーザーPath / customer data / bookmark dataを含めない
- image referenceにはdeterministicな架空fixtureだけを描画する

Removal Strategy:

- `SchneeGlassVisualSnapshotTests`とreference PNGを削除
- `Scripts/update-visual-snapshots.sh`を削除
- canonical CIのvisual snapshot stepを削除
- `Package.swift`のSnapshotTesting dependency/product参照を削除
- `Package.resolved`のSnapshotTesting関連pinを削除

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
