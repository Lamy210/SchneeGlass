# ADR-0008: Pin the Physical Copy Destination Directory

- Status: Accepted
- Scope: v0.1+
- Extends: ADR-0003, ADR-0004

## Context

SchneeGlass already pins the exact source inode from authoritative Drop planning through copy, and
pins the app-created staging inode through verification/commit. The destination parent directory was
still represented by a URL between those boundaries.

A pathname is not stable mutation authority. After Drop planning, another process can rename the
selected directory and create a different directory or symlink at the old pathname. Path-based
staging creation or commit can then target a physical directory that was never authorized by the
session. A separate `fileExists` check before rename also cannot make the no-overwrite rule atomic.

The v0.1 safety contract requires:

1. a destination pathname replacement must never redirect mutation to the replacement object,
2. staging creation must remain exclusive and no-follow,
3. final-name commit must never replace a pre-existing entry,
4. recovery authority must remain attached only to the exact app-created staging inode.

## Decision

Production pinned-source copy binds one physical destination directory per copy batch using
`DestinationDirectoryLeaseRegistry`.

Binding performs all of the following before mutation begins:

- open destination with `O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW`,
- verify the open descriptor still matches the destination pathname,
- require a directory-specific resource identifier from the acquired access or authoritative plan,
- compare available `FolderAccessHandle` fingerprint values,
- compare the authoritative `DestinationDescriptor` resource identifier,
- require the volume to advertise exclusive rename support.

A volume identifier alone is not sufficient because it cannot distinguish two directories on the
same filesystem. If both the acquired access and authoritative plan lack a directory resource
identifier, production mutation fails closed rather than accepting an identity that cannot detect a
planning-to-execution directory replacement.

Every operation ID in the batch is then associated with that same open directory descriptor plus its
single-component staging/final filenames.

### Staging creation

Production staging creation uses:

```text
openat(destinationDirectoryFD, stagingName,
       O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600)
```

`PendingCopyFileIdentity` verifies the open staging descriptor against the directory entry with
`fstatat(..., AT_SYMLINK_NOFOLLOW)` before and after replacing any inherited proof and minting the
fresh recovery xattr token.

The production path does not re-resolve the destination directory pathname to create staging data.

### Final commit

`PinnedDestinationStagingCommitter` reopens and verifies the staging entry relative to the pinned
parent descriptor, validates size and recovery token, and commits with:

```text
renameatx_np(destinationDirectoryFD, stagingName,
             destinationDirectoryFD, finalName,
             RENAME_EXCL)
```

`RENAME_EXCL` is required so a final entry that appears after preflight cannot be overwritten by a
check/rename race. A collision remains a normal fail-closed copy failure and the existing final item
is unchanged.

The older `InternalStagingCommitter` remains available for focused internal tests/support code, but
production `PinnedSourceFileCopying` uses only the descriptor-relative committer.

### Unsupported volumes / identities

If Foundation does not report `volumeSupportsExclusiveRenaming == true`, production Drop execution
fails closed. Likewise, if no directory-specific resource identity is available to compare planning
and execution, production Drop execution fails closed. v0.1 does not silently fall back to a weaker
path-based or volume-only identity implementation.

`FoundationDropFileSystemInspector` exposes the same prerequisite as
`StorageCapabilities.supportsSafeDestinationCommit`. Native Drop preview and authoritative planning
both require that capability to be explicitly `true`; `false` and unknown (`nil`) are rejected before
showing an executable copy plan. The planner reports this specifically as
`DropRejection.destinationCopySafetyUnsupported`, rather than conflating it with a disconnected or
missing destination. Presentation can therefore explain the filesystem limitation without suggesting
that reconnecting the same folder will fix it. The descriptor-bound execution checks remain
authoritative and are repeated at mutation time rather than trusting preview state.

Network destinations remain unsupported independently of this decision.

## Recovery semantics

Pending Copy metadata is written before staging mutation exactly as before.

- staging/final existence checks in the production engine resolve against the pinned directory FD,
- a staging copy or commit failure keeps the record whenever the physical staging entry still exists,
- a successful exclusive rename removes the record using the existing cleanup flow,
- ownership proof remains the random xattr token attached to the exact staging/final inode.

If the destination pathname is renamed after the directory descriptor is bound, subsequent
filesystem mutation continues to address the originally authorized physical directory, never a new
object created at the old pathname. Bookmark-based reconnect/recovery remains responsible for
locating that selected folder across moves.

## Enforcement

`Scripts/verify-file-safety.sh` allowlists `renameatx_np` only in
`PinnedDestinationStagingCommitter.swift` and continues to allow destination staging creation only in
the production source-copy boundary.

Regression tests must cover:

- destination rename/recreate between authoritative planning and execution,
- missing directory-specific identity rejection,
- existing final entry preservation,
- descriptor-relative commit after destination pathname replacement,
- source/destination lease cleanup on failure and success,
- Drop preview/planning rejection when safe destination commit capability is false or unknown,
- preservation of the distinct destination-copy-safety rejection through native preview/planning.

## Consequences

Advantages:

- destination mutation authority is physical rather than pathname-based,
- destination replacement cannot redirect a copy,
- no-overwrite commit is atomic at the filesystem boundary,
- source, destination, staging, and recovery identity now all have explicit descriptor-backed
  boundaries,
- drag feedback no longer advertises a copy that production execution already knows it cannot safely
  commit,
- unsupported filesystem safety is not misreported as a reconnectable destination outage.

Costs:

- production Drop execution is unavailable on volumes without exclusive rename support,
- production Drop execution is unavailable when a directory-specific resource identity cannot be
  established,
- POSIX-specific implementation and tests increase,
- production commit no longer relies on `FileManager.moveItem`/`NSFileCoordinator` for the final
  local rename; network destinations are already outside v0.1 scope.
