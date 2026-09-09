# SchneeGlass Release Policy

This document defines the v0.1 release baseline. An unsigned build is never a public production release.

## Current state

The v0.1 production release automation is **code complete**.

SchneeGlass currently has CI and workflows for:

- unsigned Release Candidate validation
- Developer ID signing in a temporary keychain
- post-sign signature / entitlement / Hardened Runtime verification
- Apple notarization with `notarytool`
- notarization ticket stapling and validation
- Gatekeeper assessment
- final SHA-256 integrity manifest
- signed/notarized candidate artifact and release evidence
- Manual QA-gated promotion to an immutable GitHub Release

The remaining production gates are operational validation: configure the protected release environment and credentials, verify repository release governance, produce the first real signed/notarized candidate, complete Manual QA, and publish the first immutable v0.1 Release. These are tracked in Issue #33.

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

## Production candidate workflow

`.github/workflows/production-release.yml` is the Developer ID / notarization control plane.

The actual signing job only runs when all of the following are true:

- event is manual `workflow_dispatch`
- explicit sign/notarize confirmation is true
- ref is `main`
- credential-free preflight passed
- protected `production-release` environment permits the job

PR validation runs only credential-free checks. It verifies shell syntax, production preflight, and that the signing script fails closed when credentials are absent. PR validation must never produce a signed production artifact.

Production flow:

```text
main source
  ↓
release metadata / credential preflight
  ↓
temporary keychain
  ↓
Developer ID Application identity validation
  ↓
Release archive + Developer ID signing
  ↓
codesign / authority / Team ID / Hardened Runtime / timestamp
  ↓
signed entitlement verification
  ↓
notarytool submit --wait
  ↓
status == Accepted
  ↓
stapler staple + validate
  ↓
Gatekeeper assessment
  ↓
final signed ZIP
  ↓
SHA-256 manifest + release evidence
  ↓
Actions artifact for Manual QA
```

The candidate is **not** automatically published.

App Sandbox remains enabled even though direct Developer ID distribution does not require it. Hardened Runtime remains mandatory for the notarized production path.

See [`docs/adr/0006-developer-id-direct-distribution.md`](docs/adr/0006-developer-id-direct-distribution.md).

## Production publication workflow

`.github/workflows/publish-release.yml` promotes a successful signed/notarized candidate only after Manual QA.

The publication job is restricted to:

- manual `workflow_dispatch`
- `main`
- explicit Manual QA confirmation
- explicit repository release-immutability confirmation
- explicit publish confirmation
- protected `production-release` environment

Before creating a Release it revalidates:

- candidate run belongs to `Production Release Candidate`
- candidate event is `workflow_dispatch`
- candidate run completed successfully
- candidate was built from `main`
- candidate workflow head SHA is valid
- `RELEASE_EVIDENCE.txt` version matches the requested version
- notarization status is `Accepted`
- codesign / stapler / Gatekeeper evidence is present
- evidence commit SHA equals candidate workflow head SHA
- expected archive is present in `SHA256SUMS`
- SHA-256 self-check passes
- candidate commit exists and is an ancestor of current `main`
- target tag does not already exist
- target GitHub Release does not already exist

Publication is two-phase:

1. create a Draft Release and upload/verify assets
2. publish only after Draft asset validation

After publication, `isImmutable` must be `true`. A mutable Release must not be left as the official production Release.

Expected public assets:

```text
SchneeGlass-X.Y.Z.zip
SHA256SUMS
RELEASE_EVIDENCE.txt
```

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

A production macOS release must not be published until all of the following are green:

- canonical CI and compatibility CI
- release metadata validation
- AddressSanitizer baseline
- scheduled/manual diagnostics appropriate for the release window
- Developer ID Application signing using credentials stored outside the repository
- Hardened Runtime preserved
- App Sandbox entitlements verified after signing
- `codesign --verify --deep --strict` PASS
- Apple notarization status = `Accepted`
- notarization ticket stapled to the distributed app
- `xcrun stapler validate` PASS
- Gatekeeper assessment PASS
- final SHA-256 artifact manifest
- final install/launch Manual QA on the supported macOS baseline
- repository release immutability enabled
- publication workflow revalidation PASS
- final GitHub Release reports `isImmutable=true`

Private keys, certificates, passwords, API keys, and notarization credentials must never be committed to this public repository.

## Credential boundary

Signing/notarization credentials come from the protected `production-release` environment and exist only for the lifetime of the release job.

The production script uses a temporary keychain for imported Developer ID material and removes temporary credential material during job teardown.

Repository files may document secret/variable names and required formats, but must never contain actual credential values or encoded certificate/key material.

See [`docs/RELEASE_CREDENTIALS.md`](docs/RELEASE_CREDENTIALS.md).

## Repository governance boundary

The release code cannot prove all GitHub repository settings by itself. Before first publication, Issue #33 requires human verification of:

- release immutability enabled
- `main` branch protection / ruleset
- unvalidated direct pushes to release source sufficiently restricted
- Bootstrap CI treated as a required release check
- production environment approval/deployment protection where available

The GitHub integration used during development may not have Administration read access, so lack of API visibility must not be interpreted as proof that those settings are enabled.

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

## Remaining v0.1 release work

The remaining work is operational, not missing release-pipeline code:

1. configure `production-release` environment credentials/variables
2. enable and verify repository release immutability
3. verify `main` branch/release governance
4. run the first real Developer ID signed/notarized candidate
5. complete [`docs/MANUAL_QA.md`](docs/MANUAL_QA.md) against that exact candidate
6. run `Publish Production Release`
7. verify the first immutable public v0.1 Release and record its run/tag/checksum evidence
