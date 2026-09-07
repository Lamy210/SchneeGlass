# ADR 0004: Pending Copy Recovery Semantics

## Status

Accepted for v0.1.

## Context

SchneeGlass v0.1 performs copy-only file operations through an app-owned staging file:

```text
source
  ↓ copy
.schneeglass-copy-<operation-uuid>.partial
  ↓ internal commit
final filename
```

A crash, process termination, disk-full condition, collision race, or metadata-cleanup failure can leave recovery metadata, a staging file, a final file, or a combination of them.

Recovery must not turn incomplete knowledge into destructive behavior.

## Decision

Recovery is split into three explicit phases:

```text
Persisted PendingCopyRecord
        ↓
Read-only inspection
        ↓
PendingCopyRecoveryDisposition
        ↓
Pure Recovery Action planning
        ↓
Explicit user action / later coordinator
```

### Ownership proof

A staging item is considered eligible for owned-staging recovery only when all of the following hold:

1. a `PendingCopyRecord` exists,
2. the record belongs to the supplied destination `GlassID`,
3. `stagingFilename` exactly equals
   `.schneeglass-copy-<record.operationID lowercased UUID>.partial`,
4. staging and final names are single path components,
5. the observed staging item is a regular file, not a directory, package, alias, or symbolic link.

Prefix-only matching is insufficient.

### Final file ownership

After restart, the existence, name, and size of a final file are not sufficient proof that SchneeGlass owns that final file.

Therefore recovery must never automatically delete, replace, rename, or overwrite a final file.

A final-only state may be revealed to the user and its recovery metadata may be explicitly dismissed, but the final file remains untouched.

### Conflict handling

When both staging and final files exist, the state is a conflict.

Recovery may reveal both and may later offer explicit cleanup of the proven app-owned staging file. It must not silently discard metadata or mutate the final file.

### Invalid or unexpected states

Malformed metadata, path traversal, destination mismatch, or an unexpected filesystem item type does not produce mutation actions.

The UI should surface diagnostics/reconnect/review rather than guessing.

## v0.1 automatic behavior

No user-file mutation is automatic.

The current Recovery Action Planner only determines which actions are eligible to be shown. Execution of owned-staging removal is a separate mutation boundary and requires an explicit user-initiated action.

## Consequences

Advantages:

- prevents prefix-based accidental deletion,
- keeps final user-visible files safe after ambiguous crashes,
- makes Recovery Center behavior deterministic and testable,
- gives AI-assisted implementation a narrow mutation boundary.

Trade-offs:

- some stale metadata can remain until user review,
- ambiguous final-only states are intentionally conservative,
- Recovery UI must distinguish metadata cleanup from file cleanup.
