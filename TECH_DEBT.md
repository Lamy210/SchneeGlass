# SchneeGlass Technical Debt Register

SchneeGlassでは「技術負債を完全にゼロにする」ことではなく、**意図しない負債を作らないこと**を目標とします。

Intentional Simplificationには必ず理由とRevisit Triggerを付けます。

---

## DEBT-001 — FSEvents後のFull Direct-child Snapshot

### Current

FSEvents受信後、差分PatchではなくFolder直下Snapshotを再構築する設計。

### Reason

v0.1ではCorrectnessとRecovery容易性を優先するため。

### Revisit Trigger

```text
500-item snapshotがPerformance Baselineを継続的に超える
または
実測でUI responsivenessへ影響する
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

## DEBT-004 — macOS App Target未作成のBootstrap期間

### Current

SPM Package / Domain / Application / Test / CI Guardを先に構築し、Xcode App TargetはまだRepositoryへ追加していない。

### Reason

この作業環境では実際のXcodeによるApp Target生成・`project.pbxproj` validationができないため、未検証pbxprojを手書きCommitしない。

### Revisit Trigger

Xcodeを利用可能なmacOS環境でBootstrapを継続するとき。

### Exit Criteria

```text
Xcode App Target generated
Debug build PASS
Release build PASS
Local SchneeGlassKit linkage PASS
SchneeGlass.entitlements linkage PASS
```

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
