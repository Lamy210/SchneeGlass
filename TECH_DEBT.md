# SchneeGlass Technical Debt Register

SchneeGlassでは「技術負債を完全にゼロにする」ことではなく、**意図しない負債を作らないこと**を目標とします。

Intentional Simplificationには必ず理由とRevisit Triggerを付けます。

---

## DEBT-001 — FSEvents後のFull Direct-child Snapshot

### Current

FSEvents受信後、差分PatchではなくFolder直下Snapshotを再構築する設計。

v0.1の表示上限は500 itemsで、`.github/workflows/snapshot-performance.yml`により対象変更PR・manual dispatch・weekly scheduleでperformance baselineを継続測定する。

Baseline testは501 direct-child filesを作成し、500-item truncation状態を3回snapshotする。`ProcessInfo.systemUptime`のmonotonic clockを使用し、worst latencyが`0.5s`未満であることをregression ceilingとして検証する。

PR #39導入時のGitHub-hosted macOS 26 / Xcode 26.6 runner実測では、最終runが以下だった。

```text
average = 0.055926s
worst   = 0.059213s
ceiling = 0.500000s
```

### Reason

v0.1では差分Patchの複雑性よりCorrectness、Recovery容易性、最終filesystem stateとの収束を優先するため。

### Impact

Folder changeごとにdirect-child metadataを再取得するため、item数・storage latency・metadata取得コストが増えるとUI refresh latencyへ影響する可能性がある。

### Revisit Trigger

```text
500-item snapshotが0.5s baseline ceilingを継続的に超える
または
実測でUI responsivenessへ影響する
```

単発のshared CI runner jitterだけでは即座に設計変更せず、複数runと実機挙動を確認する。

### Exit Criteria

差分更新へ移行する場合でも、以下を維持できること。

```text
final FolderSnapshot == filesystem source of truth
startup/event raceで変更を取りこぼさない
recovery時にfull rescan可能
複雑化に見合う実測改善がある
```

---

## DEBT-002 — Configuration PersistenceにJSONを使用

### Current

v0.1 ConfigはCodable JSON + Atomic Write + Backup。

### Reason

Configuration量が小さく、DBを導入する価値がないため。

### Revisit Trigger

```text
Operation Journal
Safe Move / Undo
複雑なRecovery Query
```

が必要になった時点。

候補:

```text
GRDB / SQLite
```

---

## DEBT-003 — Sequential Copy Only

### Current

```text
maxConcurrentCopies = 1
```

### Reason

Recovery、failure semantics、I/O competition、Test determinismを単純化するため。

### Revisit Trigger

実測でSequential Copyが主要UX bottleneckになった場合。

---

## Resolved Debt

### DEBT-004 — macOS App Target未作成のBootstrap期間

**Status: RESOLVED**

解消内容:

```text
SchneeGlass.xcodeproj added
Shared SchneeGlass scheme added
Local SchneeGlassKit linkage validated
macOS 15 Debug app build PASS
macOS 26 / Xcode 26.6 Debug app build PASS
macOS 26 / Xcode 26.6 Release app build PASS
SchneeGlass.entitlements source validation PASS
Unsigned CI app artifact generation PASS
```

App Targetは推測上の未検証pbxprojとして残さず、GitHub-hosted macOS runner上の`xcodebuild`で継続検証する状態へ移行した。

---

## 負債追加ルール

新規Entryには最低限以下を記録する。

```text
Current
Reason
Impact
Revisit Trigger
Exit Criteria（定義可能なら）
```

「一時的」「あとで直す」だけの記録は禁止する。
