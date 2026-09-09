# ADR 0005: Configuration Persistence and Recovery Semantics

## Status

Accepted for v0.1.

## Context

SchneeGlass stores Glass layout, folder references, placement, and related configuration as application-owned metadata.

Configuration corruption must not make the user's files inaccessible, but careless recovery can still destroy useful application state. In particular, an older application must not overwrite a configuration produced by a newer schema that it does not understand.

## Decision

v0.1 uses a versioned Codable JSON envelope:

```text
Configuration/
├── config.json
├── Backups/
│   └── backup-<timestamp>-<uuid>.json
└── Preserved/
    └── current-<timestamp>-<uuid>.json
```

Current schema version:

```text
schemaVersion = 1
```

All Configuration-owned filesystem I/O uses the physical owned-state boundary defined by ADR 0007. `Configuration`, `Backups`, and `Preserved` must be physical directories opened without following symlinks, and state leaf files must be physical regular files.

### Normal load

- missing `config.json` means an empty configuration,
- valid schema 1 configuration is decoded and returned,
- malformed current configuration produces `corruptCurrent`,
- an unknown/future schema produces `unsupportedSchemaVersion`,
- unsafe Configuration directory / leaf topology produces `unsafeStorageTopology`,
- normal load never silently falls back to a backup.

### Normal save

Before replacing `config.json`, SchneeGlass must read and validate the current configuration when one exists.

- valid current configuration is copied to an app-owned backup,
- malformed current configuration blocks the save,
- unknown/future schema blocks the save,
- unsafe owned-state topology blocks the save,
- a normal save never overwrites unreadable or unsupported current state,
- the new configuration is written atomically through `PhysicalStateStore`.

The atomic write uses a same-directory exclusive temporary regular file, `fsync`, identity revalidation, and `renameat`. The successful `renameat` is the final fallible visible-state commit step.

This prevents an older or damaged process from destroying configuration that may still be recoverable.

### Backup policy

SchneeGlass retains at most five app-owned backup generations.

A backup entry is eligible only when both of these are true:

1. its filename matches the strict `backup-<timestamp>-<uuid>.json` grammar,
2. the directory entry itself is a physical regular file.

The `Backups` directory is first opened as a physical no-follow directory. Listing uses the pinned directory FD and classifies entries with `fstatat(..., AT_SYMLINK_NOFOLLOW)`. Candidate bytes are read from an `O_NOFOLLOW` descriptor after `fstat` confirms a regular file.

Rotation is performed by `PhysicalStateStore.removeRegularFile`. The selected entry must be a physical regular file, its identity is rechecked, and removal uses `unlinkat` against the pinned backup directory FD. Direct recursive-capable `FileManager.removeItem` is not part of the backup rotation boundary.

The POSIX mutation calls are allowlisted only inside `SchneeGlassPOSIXSupport/PhysicalStateStore.swift` by the File Safety Guard. This does not authorize deletion of user files or arbitrary paths.

### Recovery candidates

Only backups that:

1. match the strict app backup filename format,
2. are physical regular files opened without following symlinks,
3. decode successfully,
4. use a supported schema,

are surfaced as recovery candidates.

Corrupt, unreadable, replaced, or non-regular individual backup entries remain non-restorable and are not silently selected. Unsafe `Configuration/Backups` directory topology fails the recovery listing itself rather than traversing the directory target.

### Explicit restore

Backup restore is always an explicit recovery action, but explicit user intent does not waive preservation, topology, and schema-safety requirements.

Before restore:

- a valid supported current configuration is itself backed up,
- malformed **but readable** current bytes are preserved byte-for-byte under `Configuration/Preserved`,
- a current configuration that cannot be read from the filesystem blocks restore because SchneeGlass cannot preserve what it cannot read,
- an unknown/future schema blocks restore with `unsupportedSchemaVersion`; it is not treated as corruption and is never overwritten by an older binary,
- unsafe Configuration / Backups / Preserved topology blocks restore with `unsafeStorageTopology`,
- the selected backup is fully decoded and validated before current state is replaced.

Only after all applicable current-state preservation checks and backup validation succeed is the selected backup written atomically to `config.json`.

### No silent rollback

SchneeGlass never automatically changes configuration generations merely because the current configuration failed to decode.

Recovery UI must present the failure and let the user select an available valid backup or another recovery path. An explicit restore still fails closed when the existing current state is unreadable, belongs to an unsupported schema, or the owned-state topology is unsafe.

## Consequences

Advantages:

- corrupt current state is not silently hidden,
- future-schema data is protected from older binaries during normal save and explicit restore,
- explicit restore preserves potentially useful readable corrupt bytes,
- unreadable current state cannot be destroyed merely because it could not be preserved,
- Configuration directory and leaf symlinks are not traversed,
- backup rotation is bounded,
- backup reads and rotation do not follow symlink replacements,
- all destructive application-metadata cleanup uses one shared auditable non-recursive POSIX boundary.

Trade-offs:

- startup recovery requires an explicit UI path,
- filesystem-level read/topology failures may require the user to repair permissions or app-owned metadata before restoring,
- preserved corrupt configurations may require later retention/cleanup policy,
- JSON remains less suitable than a database for future operation journals and Undo.
