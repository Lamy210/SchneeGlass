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

Descriptor-derived POSIX directory identity is the primary current-session continuity proof.

`FolderAccessHandle.runtimeDirectoryIdentity` carries a non-persistent `RuntimeDirectoryIdentity` derived from the directory object's `st_dev` and `st_ino`. When that identity is available, bookmark refresh, snapshot-root verification, Drop planning, and copy destination binding validate the selected physical directory against it. Path-based capability reads are bracketed by POSIX identity checks where necessary, and copy execution still pins the destination directory descriptor before mutation.

`RuntimeDirectoryIdentity` is intentionally not Codable and must never become persisted folder authority.

For access establishment, `ResourceFingerprint` is retained only as a compatibility fallback for filesystems or locations where descriptor-derived runtime identity cannot be obtained. In that fallback path, Foundation `volumeIdentifier` / `fileResourceIdentifier` values may be observed for the active access, but they remain boot/session-local and must never be written into new configuration. A normal POSIX-backed access therefore leaves `FolderAccessHandle.fingerprint` unset.

Snapshot-root continuity follows the same hierarchy. If an acquired runtime directory identity exists, `NativeFolderSnapshotReader` verifies the root before and after enumeration using POSIX device/inode identity and does not read or stringify Foundation root identifiers. If acquired POSIX proof is unavailable, the reader retains the Foundation root-fingerprint comparison as a compatibility fallback.

Direct-child `FileIdentity.resourceIdentifier` remains separate presentation/list identity metadata. It may still use Foundation file resource identifiers, but it is not folder access authority, persisted folder identity, or copy mutation authority.

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

For current-session continuity during access establishment, bookmark refresh, and snapshot-root verification:

- if POSIX runtime identity is available before an asynchronous safety boundary, disappearance of that identity at revalidation fails closed,
- a changed POSIX runtime identity is treated as replacement,
- `ResourceFingerprint` or snapshot root-fingerprint comparison is used only when acquired POSIX runtime identity is unavailable,
- no pathname-only or volume-only value is promoted to persisted authority.

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
- normal POSIX-backed access establishment and snapshot-root verification use documented descriptor metadata instead of opaque Foundation root fingerprint values,
- Foundation folder/root fingerprints are isolated to compatibility fallback paths,
- current copy descriptor pinning and mutation safety are not weakened.

### Trade-offs

- normal access may rely on bookmark resolution alone when persistent metadata is unavailable,
- automatic reconnect is unavailable on volumes that cannot provide both persistent identity dimensions,
- fallback environments without POSIX runtime identity still depend on Foundation's boot-local resource identifiers for live folder/root comparison,
- direct-child presentation identity still uses Foundation file resource identifiers and remains a separate future hardening concern if its role changes,
- POSIX runtime identity is process/session-local and therefore cannot replace the security-scoped bookmark or restart-safe persistent metadata.

## Verification

Required automated coverage:

- legacy schema-v1 `fingerprint` JSON decodes,
- re-saving legacy configuration removes the boot-local fingerprint,
- persistent identity round-trips,
- a legacy boot-local fingerprint mismatch does not reject a valid bookmark,
- persisted restart-safe identity mismatch fails closed,
- persisted identity becoming unavailable fails closed,
- reconnect requires exact persistent directory identity,
- POSIX-backed access does not read or populate a Foundation `ResourceFingerprint`,
- stable POSIX identity survives stale-bookmark refresh,
- POSIX identity replacement or disappearance during stale-bookmark refresh fails closed,
- Foundation fingerprint refresh comparison remains covered as an explicit POSIX-unavailable fallback,
- POSIX-backed snapshot-root verification performs no Foundation root-fingerprint read,
- snapshot-root replacement or identity disappearance fails closed under POSIX verification,
- Foundation snapshot-root comparison remains covered as an explicit POSIX-unavailable fallback.

Required release QA additionally includes application restart and full macOS system restart with an existing Glass.
