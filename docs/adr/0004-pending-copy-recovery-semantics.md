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

Recovery is split into explicit phases:

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

A staging item is eligible for owned-staging cleanup only when all of the following hold:

1. a `PendingCopyRecord` exists,
2. the record belongs to the supplied destination `GlassID`,
3. `stagingFilename` exactly equals `.schneeglass-copy-<record.operationID lowercased UUID>.partial`,
4. staging and final names are single path components,
5. the observed staging item is a regular file, not a directory, package, alias, or symbolic link,
6. `PendingCopyRecord.stagingResourceIdentifier` was captured after staging creation,
7. the currently observed staging file resource identifier exactly matches the recorded identifier.

Filename or prefix matching alone is never sufficient proof for deletion.

If a staging item exists but the resource identifier is unavailable or no longer matches, Recovery may reveal the item for manual inspection but must not offer `removeOwnedStaging`.

### Resource identity capture

`SafeFileCopyEngine` records the staging file resource identifier after the staging copy exists and before commit metadata is persisted.

The identifier is used only as a best-effort local filesystem identity signal. It is not treated as a cryptographic identity and does not authorize mutation outside the exact destination/operation constraints above.

### Final file ownership

After restart, the existence, name, size, or even continuity of a resource identifier is not sufficient authority to delete a final user-visible file automatically.

Therefore recovery must never automatically delete, replace, rename, or overwrite a final file.

A final-only state may be revealed to the user and its recovery metadata may be explicitly dismissed, but the final file remains untouched.

### Conflict handling

When both staging and final files exist, the state is a conflict.

Recovery may reveal both. `removeOwnedStaging` may be offered only when the staging item still satisfies the complete ownership proof above. Recovery must not silently discard metadata or mutate the final file.

### Invalid or unexpected states

Malformed metadata, path traversal, destination mismatch, resource identity mismatch, or an unexpected filesystem item type does not produce destructive mutation actions.

The UI should surface diagnostics/reconnect/review rather than guessing.

## v0.1 automatic behavior

No user-file mutation is automatic.

The Recovery Action Planner only determines which actions are eligible to be shown. Execution of owned-staging removal is a separate mutation boundary and requires an explicit user-initiated action.

## Consequences

Advantages:

- prevents prefix-based accidental deletion,
- protects against same-name staging file replacement after a crash,
- keeps final user-visible files safe after ambiguous crashes,
- makes Recovery Center behavior deterministic and testable,
- gives AI-assisted implementation a narrow mutation boundary.

Trade-offs:

- cleanup can be withheld when the filesystem cannot provide a stable resource identifier,
- some stale metadata can remain until user review,
- ambiguous final-only states are intentionally conservative,
- Recovery UI must distinguish metadata cleanup from file cleanup.
