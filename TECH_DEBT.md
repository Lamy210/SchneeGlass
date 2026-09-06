# Technical Debt Register

SchneeGlass では「技術負債を完全に作らない」ことではなく、**意図せず・追跡不能な負債を作らないこと**を目標にします。

Intentional simplification は許可しますが、理由と revisit trigger を記録します。

## Entry Format

```text
DEBT-XXX

Status:
Area:
Current:
Reason:
Risk:
Revisit Trigger:
Resolution Direction:
Related Issue/ADR:
```

## DEBT-001 — FSEvents 後の full direct-child rescan

**Status:** Accepted for v0.1  
**Area:** Filesystem observation

### Current

FSEvents の各 debounce batch 後に、対象 Folder の direct children を再 snapshot する。

### Reason

v0.1 は差分処理の複雑性より correctness と recovery を優先する。

### Risk

非常に大量の direct children を持つ Folder では enumeration cost が増える。

### Revisit Trigger

- 500-item snapshot が performance baseline を継続的に超える
- Real-world profile で measurable UI latency が確認される

### Resolution Direction

Correctness invariant を維持したまま snapshot cache / scoped invalidation を検討する。

## DEBT-002 — JSON configuration persistence

**Status:** Accepted for v0.1  
**Area:** Persistence

### Current

Glass configuration / recovery metadata を atomic JSON で管理する。

### Reason

v0.1 の状態量には DB が過剰。

### Revisit Trigger

Safe Move / Undo / Operation Journal 導入。

### Resolution Direction

GRDB/SQLite transaction journal へ移行する。
