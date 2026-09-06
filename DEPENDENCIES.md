# Dependency Policy

SchneeGlass は Runtime dependency を最小化します。

優先順位:

```text
Apple Platform API
→ Swift official package
→ mature third-party OSS
```

## v0.1 Runtime Candidates

### KeyboardShortcuts

用途: User-customizable global keyboard shortcut。

採用理由:

- macOS global shortcut の実装・Recorder UI を自前で再実装する価値が低い
- Sandbox 対応
- Swift Package Manager 対応
- Swift 6 対応

初期 pin 候補: `3.0.1`

### swift-async-algorithms

用途: FSEvents 等の AsyncSequence debounce / event composition。

採用理由:

- Swift ecosystem の公式 package
- Combine 中心設計を避け、Swift Concurrency と統一可能

初期 pin 候補: `1.1.5`

## Test-only Candidates

- SnapshotTesting
- swift-clocks

Test-only dependency を Runtime product へ link しません。

## Future / Not v0.1

### GRDB

Safe Move / Undo / Operation Journal を導入する v0.2 で再評価します。

### Sparkle

Direct Distribution updater を導入する v0.1.1+ で再評価します。

## Dependency Admission Checklist

Runtime dependency の追加前に全項目を満たしてください。

- [ ] Apple API で十分に代替できない
- [ ] Active maintenance
- [ ] Swift 6 compatible
- [ ] Swift Package Manager support
- [ ] License acceptable
- [ ] Transitive dependencies understood
- [ ] Security history reviewed
- [ ] Removal strategy exists
- [ ] `DEPENDENCIES.md` updated
- [ ] Build/Test/Safety gates pass

`Package.resolved` は commit します。

Dependency update の auto-merge は行いません。
