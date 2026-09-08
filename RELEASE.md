# SchneeGlass Release Policy

This document defines the v0.1 release baseline. An unsigned build is never a public production release.

## Current state

SchneeGlass validates unsigned release candidates in CI, including project version metadata, Release build output, Sandbox baseline, ZIP packaging, and SHA-256 integrity.

ADR-0006 selects **Developer ID direct distribution outside the Mac App Store** for v0.1. Developer ID signing, notarization, stapling, Gatekeeper verification, and final public publication are the remaining production gates.

An unsigned CI artifact is for verification only. Do not publish it as a trusted end-user release.

## Versioning

v0.1 uses a strict release version format:

```text
MARKETING_VERSION       = X.Y.Z
CURRENT_PROJECT_VERSION = positive integer
Git tag                 = vX.Y.Z
```

Rules:

1. Debug and Release configurations must use the same `MARKETING_VERSION`.
2. Debug and Release configurations must use the same `CURRENT_PROJECT_VERSION`.
3. A release tag must exactly match `MARKETING_VERSION` after removing the leading `v`.
4. `CURRENT_PROJECT_VERSION` must increase for a newly distributed build of the same or a later marketing version.
5. Do not move or reuse a published release tag. A bad release gets a new version/build.

`Scripts/verify-release-metadata.sh` enforces rules 1–3 and validates the bundle identifier. Monotonic build-number history is a release-process requirement until a release ledger is added.

## Unsigned release candidate validation

`.github/workflows/release-candidate.yml` runs on:

- release-related Pull Requests
- manual `workflow_dispatch`
- tags matching `v*.*.*`

The workflow:

1. verifies Xcode 26.6
2. validates project version/build metadata
3. verifies a supplied/tag version matches the Xcode project
4. runs Swift Package tests
5. builds the Release app without code signing
6. verifies the app bundle/version/Sandbox baseline
7. packages the app as `SchneeGlass-X.Y.Z-unsigned.zip`
8. creates `SHA256SUMS`
9. verifies the checksum before artifact upload

The workflow has read-only repository permissions and does not create a GitHub Release.

## Production distribution path

v0.1 uses Developer ID direct distribution.

Production flow:

```text
validated source/tag
  ↓
Release build
  ↓
Developer ID Application signing
  ↓
codesign verification
  ↓
ZIP packaging
  ↓
Apple notarization via notarytool
  ↓
staple + stapler validation
  ↓
Gatekeeper assessment
  ↓
SHA-256 manifest
  ↓
immutable GitHub Release
```

App Sandbox remains enabled even though direct Developer ID distribution does not require it. Hardened Runtime remains mandatory for the notarized production path.

See [`docs/adr/0006-developer-id-direct-distribution.md`](docs/adr/0006-developer-id-direct-distribution.md).

## Integrity

Each release-candidate and production artifact must be distributed with the generated SHA-256 manifest:

```text
SHA256SUMS
```

Verification:

```bash
shasum -a 256 -c SHA256SUMS
```

A checksum proves artifact integrity relative to the manifest; it does **not** replace Apple code signing or notarization.

## Production release gates

A production macOS release must not be published until all of the following are implemented and green:

- canonical CI and compatibility CI
- release metadata validation
- Developer ID Application signing using credentials stored outside the repository
- Hardened Runtime preserved
- App Sandbox entitlements verified after signing
- `codesign --verify --deep --strict` PASS
- Apple notarization ACCEPTED
- notarization ticket stapled to the distributed app
- `xcrun stapler validate` PASS
- Gatekeeper assessment PASS
- SHA-256 artifact manifest
- final install/launch manual QA on the supported macOS baseline

Private keys, certificates, passwords, API keys, and notarization credentials must never be committed to this public repository.

## Credential boundary

Signing/notarization credentials must come from a protected CI release environment and exist only for the lifetime of the release job.

The implementation must use a temporary keychain for imported Developer ID material and clean that keychain during job teardown.

Repository files may document secret names and required formats, but must never contain actual credential values or encoded certificate/key material.

## Bad release / rollback policy

SchneeGlass does not mutate or replace an existing release artifact in place.

If a release is bad:

1. stop promoting that version
2. document the known issue
3. fix on `main`
4. increment the version/build as appropriate
5. run the complete release pipeline again
6. publish a new immutable release/tag

User-owned files remain the source of truth. Release rollback must never require automatic destructive migration of connected folders.

## Next release work

The remaining TASK-018 work is intentionally separated from the unsigned foundation:

- define protected release environment / secret contract
- import Developer ID certificate into a temporary CI keychain
- create signed Release build/export flow
- verify signature and entitlements after signing
- implement `notarytool` submission and accepted-state verification
- implement `stapler` staple / validate and Gatekeeper assessment
- define final immutable GitHub Release publication step
- add signed-release manual QA checklist
