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

### Normal load

- missing `config.json` means an empty configuration,
- valid schema 1 configuration is decoded and returned,
- malformed current configuration produces `corruptCurrent`,
- an unknown/future schema produces `unsupportedSchemaVersion`,
- normal load never silently falls back to a backup.

### Normal save

Before replacing `config.json`, SchneeGlass must read and validate the current configuration when one exists.

- valid current configuration is copied to an app-owned backup,
- malformed current configuration blocks the save,
- unknown/future schema blocks the save,
- a normal save never overwrites unreadable or unsupported current state,
- the new configuration is written atomically.

This prevents an older or damaged process from destroying configuration that may still be recoverable.

### Backup policy

SchneeGlass retains at most five app-owned backup generations.

A backup entry is eligible only when both of these are true:

1. its filename matches the strict `backup-<timestamp>-<uuid>.json` grammar,
2. the directory entry itself is a physical regular file.

List and restore operations open candidate files with `O_NOFOLLOW`, verify the opened descriptor is a regular file with `fstat`, and read bytes from that same pinned descriptor. A symlink, directory, or entry replaced with a symlink is never followed as a backup source.

Backup deletion is isolated to `ConfigurationBackupRotator`. Rotation uses POSIX `unlink` rather than recursive-capable `FileManager.removeItem`, so the mutation boundary can remove only a single directory entry and cannot recursively delete a directory if an entry changes type after selection. If a selected path is replaced by a symlink, unlink removes the symlink entry rather than following its target.

The `unlink` call is explicitly allowlisted only for `ConfigurationBackupRotator` by the File Safety Guard. It does not authorize deletion of user files or arbitrary application-support paths, and reintroducing `FileManager.removeItem` in that boundary fails the guard.

### Recovery candidates

Only backups that:

1. match the strict app backup filename format,
2. are physical regular files opened without following symlinks,
3. decode successfully,
4. use a supported schema,

are surfaced as recovery candidates.

Corrupt, unreadable, replaced, or non-regular backup entries remain non-restorable and are not silently selected.

### Explicit restore

Backup restore is always an explicit recovery action.

Before restore:

- a valid current configuration is itself backed up,
- an unreadable current configuration is preserved byte-for-byte under `Configuration/Preserved`,
- the selected backup is fully decoded and validated before current state is replaced.

The selected validated backup is then written atomically to `config.json`.

### No silent rollback

SchneeGlass never automatically changes configuration generations merely because the current configuration failed to decode.

Recovery UI must present the failure and let the user select an available valid backup or another recovery path.

## Consequences

Advantages:

- corrupt current state is not silently hidden,
- future-schema data is protected from older binaries,
- explicit restore preserves potentially useful corrupt bytes,
- backup rotation is bounded,
- backup reads and rotation do not follow symlink replacements,
- destructive application-metadata cleanup remains in a narrow auditable non-recursive boundary.

Trade-offs:

- startup recovery requires an explicit UI path,
- preserved corrupt configurations may require later retention/cleanup policy,
- JSON remains less suitable than a database for future operation journals and Undo.
