# ADR-0002: v0.1 は Copy-only とする

- Status: Accepted
- Scope: v0.1

## Context

Move/Delete/Rename はユーザーデータを直接変更し、Undo、operation journal、cross-volume semantics、crash recovery、collision policy を要求する。

v0.1 でそれらを同時に実装すると release scope と risk が大幅に増える。

## Decision

v0.1 の Drop operation は regular file の Copy のみに限定する。

禁止:

- user-owned Move
- user-owned Rename
- Delete / Trash
- Replace / Overwrite
- Recursive folder copy

Batch runtime failure 時に成功済み copy を自動削除して rollback しない。

## Consequences

- v0.1 は non-destructive promise を明確にできる
- Safe Move は v0.2 で GRDB journal/Undo と同時に設計できる
- 利便性の一部は v0.1 では intentionally deferred
