# ADR 0010: Persistent Folder Identity

- Status: Accepted
- Date: 2026-09-12

## Context

SchneeGlass persists a security-scoped bookmark for every connected folder. The original v0.1 model also persisted Foundation `volumeIdentifier` and `fileResourceIdentifier` values as strings inside `ResourceFingerprint` and compared those saved values when the bookmark was resolved later.

That persistence contract is invalid on macOS: `volumeIdentifier` and `fileResourceIdentifier` are not guaranteed to remain stable across a system restart. Treating them as durable identity can therefore reject a valid bookmark after reboot. Converting opaque Foundation identifiers with `String(describing:)` also does not establish a documented persistent comparison format.

At the same time, SchneeGlass still needs strong current-session identity checks around asynchronous bookmark refresh, snapshots, Drop planning, and copy execution to prevent pathname replacement from becoming mutation authority.

## Decision

### Persistent resource reference

The security-scoped bookmark is the primary persistent folder reference and permission authority.

`FolderSource` may additionally persist `PersistentFolderIdentity`:

- `volumeUUIDString`
- `documentIdentifier`

These values are supplemental proof only. A filesystem that does not expose restart-safe metadata remains usable through its valid security-scoped bookmark.

A document identifier is never treated as globally unique by itself. Automatic same-folder reconnect requires both the persistent volume UUID and document identifier.

### Runtime identity

`ResourceFingerprint` is boot/session-local. It may be used while a resolved security-scoped access is active to detect replacement across an asynchronous operation, but new configuration persistence must never encode it.

Existing runtime copy and snapshot code continues to use the current fingerprint representation in this change. Replacing remaining opaque `String(describing:)` comparisons with a documented session-local representation such as descriptor-backed `st_dev`/`st_ino` is a separate hardening change so the persistent-identity migration does not simultaneously rewrite copy authority.

### Legacy configuration migration

Schema-v1 configuration and backups that contain `source.fingerprint` remain decodable.

The legacy fingerprint is not used as restart-safe authority. After a bookmark resolves successfully, Application persistence receives a refreshed `FolderSource` containing the current persistent metadata when available. The next encode omits the legacy runtime fingerprint.

This is a compatible field migration and does not require a schema-version bump because:

- old schema-v1 data remains readable,
- the new `persistentIdentity` field is optional,
- the removed-on-write `fingerprint` field is optional when decoding.

### Fail-closed rules

If a configuration already contains persistent identity proof:

- a different observed value is `resourceReplacementDetected`,
- a previously-recorded identity dimension becoming unavailable fails access establishment,
- a metadata read failure fails access establishment.

If no persistent proof was previously saved, inability to obtain supplemental persistent metadata does not invalidate an otherwise valid security-scoped bookmark.

### Pending Copy destination reconnect

Reconnect can replace a saved bookmark only when the saved and user-selected folders both expose matching:

- `volumeUUIDString`, and
- `documentIdentifier`.

If either dimension is unavailable, automatic reconnect fails closed rather than guessing from a pathname or boot-local resource identifier.

## Consequences

### Positive

- normal system restart no longer turns a valid bookmark into a false replacement solely because boot-local Foundation identifiers changed,
- legacy configuration remains loadable and migrates without destructive reset,
- filesystems without persistent metadata remain usable for normal bookmark-based access,
- reconnect remains strict because it changes persisted access authority,
- current copy descriptor pinning and mutation safety are not weakened.

### Trade-offs

- normal access may rely on bookmark resolution alone when persistent metadata is unavailable,
- automatic reconnect is unavailable on volumes that cannot provide both persistent identity dimensions,
- runtime `ResourceFingerprint` remains a transitional boot-local abstraction until the separate session-identity hardening change.

## Verification

Required automated coverage:

- legacy schema-v1 `fingerprint` JSON decodes,
- re-saving legacy configuration removes the boot-local fingerprint,
- persistent identity round-trips,
- a legacy boot-local fingerprint mismatch does not reject a valid bookmark,
- persisted restart-safe identity mismatch fails closed,
- persisted identity becoming unavailable fails closed,
- reconnect requires exact persistent directory identity.

Required release QA additionally includes application restart and full macOS system restart with an existing Glass.
