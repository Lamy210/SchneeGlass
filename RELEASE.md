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
- signed bundle metadata evidence derived from the final ZIP
- strict `RELEASE_EVIDENCE.txt` schema v1 validation
- exact Production Release Candidate workflow identity validation
- final SHA-256 integrity manifest
- signed/notarized candidate artifact and release evidence
- public build-number monotonicity validation
- source-bound Bootstrap CI governance validation before production publication
- Manual QA-gated promotion to an immutable GitHub Release

The remaining production gates are operational validation: configure the protected release environment and credentials, configure repository release governance, produce the first real signed/notarized candidate, complete Manual QA, and publish the first immutable v0.1 Release. These are tracked in Issue #33.

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
4. `CURRENT_PROJECT_VERSION` must increase for every newly distributed public build, including later marketing versions.
5. Do not move or reuse a published release tag. A bad release gets a new version/build.

`Scripts/verify-release-metadata.sh` enforces rules 1–3 and validates the bundle identifier.

Rule 4 is enforced automatically during production publication by `Scripts/verify-release-build-history.sh`. The workflow downloads `RELEASE_EVIDENCE.txt` from all existing non-draft Releases, treats prereleases as distribution history, computes the maximum published `bundle_build`, and requires:

```text
first public Release:
  history count == 0 → PASS

subsequent public Release:
  candidate bundle_build > max(published bundle_build)
```

Missing, malformed, or unsupported historical evidence fails closed before Draft Release creation.

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

For pull requests, Release Candidate Validation uses PR-scoped concurrency and cancels superseded runs when a newer commit is pushed to the same PR. Tag-triggered and manual validations use a per-run concurrency key, so separate release validations remain independent.

## Production candidate workflow

`.github/workflows/production-release.yml` is the Developer ID / notarization control plane.

The actual signing job only runs when all of the following are true:

- event is manual `workflow_dispatch`
- explicit sign/notarize confirmation is true
- ref is `main`
- credential-free preflight passed
- protected `production-release` environment permits the job

PR validation runs only credential-free checks. It verifies shell syntax, production preflight, fail-closed behavior without credentials, strict evidence-schema fixtures, and unknown-key rejection. PR validation must never produce a signed production artifact.

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
SHA-256 manifest
  ↓
initialize RELEASE_EVIDENCE.txt schema v1
  ↓
read final signed ZIP Info.plist
  ↓
record bundle identifier / version / build
  ↓
record exact source commit SHA
  ↓
strict complete evidence validation
  ↓
Actions artifact for Manual QA
```

The signed ZIP itself is the authority for:

```text
bundle_identifier=io.github.lamy210.schneeglass
bundle_version=X.Y.Z
bundle_build=<positive integer>
```

Before those bundle metadata keys are appended, the recorder must positively prove each key is absent from the existing evidence. A grep/probe failure is not equivalent to absence and must fail closed before mutating `RELEASE_EVIDENCE.txt`.

### RELEASE_EVIDENCE schema v1

`RELEASE_EVIDENCE.txt` is a strict contract, not a free-form log.

Schema initialization is also fail-closed: an existing `schema_version` is rejected, confirmed absence is required before prepending `schema_version=1`, and a probe failure must leave the evidence unchanged.

Required keys, each exactly once:

```text
schema_version
version
notarization_id
notarization_status
codesign
stapler
gatekeeper
bundle_identifier
bundle_version
bundle_build
commit_sha
```

Required-key occurrence enumeration is fail-closed. A legitimate grep no-match is normalized to zero and rejected by the exactly-once rule; an enumeration error or malformed/non-numeric count is not treated as a trustworthy key count.

Validation rules include:

- `schema_version=1`
- no unknown keys
- no blank or malformed lines
- requested version must match
- notarization ID must have UUID shape
- `notarization_status=Accepted`
- `codesign=verified`
- `stapler=validated`
- `gatekeeper=accepted`
- `bundle_identifier=io.github.lamy210.schneeglass`
- `bundle_version` must equal requested version
- `bundle_build` must be a positive integer
- `commit_sha` must equal the exact candidate workflow head SHA

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
- explicit release-governance confirmation
- explicit publish confirmation
- protected `production-release` environment

`confirm_release_governance=true` remains a human attestation that release-source governance was reviewed. The workflow additionally performs read-only automatic checks that `main` is protected and that both Bootstrap CI jobs are configured as required status checks from the GitHub Actions App. This does not replace human review of repository settings that are not available through the workflow's non-Administration token, such as the pre-publication release-immutability setting and broader direct-push/bypass policy.

### Required Bootstrap CI governance

Immediately before publication, the workflow reads the current `main` branch summary and active branch rules. It combines classic branch-protection `checks[]` with active ruleset `required_status_checks` and requires these exact contexts:

```text
Canonical / Xcode 26.6 / App Build / Safety Guards
Compatibility / macOS 15 / App Build
```

Both contexts must be explicitly source-bound to the GitHub Actions App (`app_id` / `integration_id` `15368`). Legacy classic `contexts` without an explicit app binding, a ruleset check with no `integration_id`, or a same-named check bound to another App does not satisfy production release governance.

This is deliberately stricter than name-only matching: an unrelated integration must not be able to satisfy the production release gate merely by publishing a check with the expected name.

### Candidate workflow identity

Publication does not trust the display name alone. The selected Actions run must satisfy all of the following:

```text
name       = Production Release Candidate
path       = .github/workflows/production-release.yml
event      = workflow_dispatch
status     = completed
conclusion = success
branch     = main
head_sha   = 40-character lowercase commit SHA
```

This prevents a lookalike workflow with the same display name from being promoted.

### Publication revalidation

Before creating a Release it revalidates:

- current `main` reports `protected=true`
- both exact Bootstrap CI job contexts are required and explicitly bound to the GitHub Actions App
- exact candidate workflow identity above
- strict schema v1 `RELEASE_EVIDENCE.txt`
- requested version
- signed bundle identifier
- signed bundle version
- positive signed bundle build
- notarization / codesign / stapler / Gatekeeper state
- evidence commit SHA equals candidate workflow head SHA
- `SHA256SUMS` contains exactly one entry with a 64-hex digest, exactly two separator spaces, and the exact literal candidate archive filename
- SHA-256 self-check passes for that exact candidate archive
- all existing public Release build evidence is readable and valid; schema/build key enumeration failures or malformed counts fail closed
- candidate `bundle_build` is greater than the maximum public Release build when history exists
- candidate commit exists and exactly matches the freshly fetched current `main` commit before Draft creation
- target tag absence is positively established (`git ls-remote --exit-code` status 2); an unavailable/failed tag probe fails closed
- target GitHub Release absence is positively established by a fail-closed paginated API enumeration; an unavailable Release probe fails closed

Publication captures the run-created Draft identity after Draft creation succeeds:

1. create an asset-free Draft Release targeting the exact candidate SHA
2. verify `targetCommitish` equals that candidate SHA
3. upload ZIP / `SHA256SUMS` / `RELEASE_EVIDENCE.txt`
4. require the Draft asset set to contain exactly those three assets, with no missing, extra, or duplicate names
5. re-fetch `origin/main` and require the candidate SHA to still equal the exact current `main` commit
6. publish
7. require `isImmutable=true`
8. re-read the immutable public Release and require the same exact three-asset set
9. re-read the public Release `targetCommitish` and require the exact candidate SHA
10. resolve the final remote release tag and require it to point to the exact candidate SHA
11. re-read the public Release `databaseId` and require exact equality with the run-created Draft Release ID

If publication reports `isImmutable=false`, the workflow fails without deleting or editing the remote Release or tag. It emits manual-reconciliation guidance containing the target tag and captured Release ID so an operator can inspect the exact public state before taking any corrective action. Automatic deletion is intentionally prohibited because the mutable-state proof and a later destructive delete cannot be made atomic; the same tag/Release may change between those operations. Pre-existing tag/Release names are still rejected before creation.

Before this run's own publication command succeeds, EXIT cleanup is intentionally non-destructive. It removes only local temporary release data; it may perform read-only diagnostics, but it never deletes or edits a remote GitHub Release or tag. Any failure after this run creates a Draft emits manual-reconciliation guidance containing the target tag and the captured Release ID (or explicitly reports that the ID was unavailable if identity capture itself failed). The operator must inspect and reconcile that remote state before retrying. This avoids relying on a non-atomic gap between "still a mutable Draft" proof and an unconditional Release DELETE.

If final public asset or provenance verification is unavailable or inconsistent after publication, the workflow fails without destructive cleanup and requires manual reconciliation because the public state may already be immutable.

The public Release must contain exactly these three assets and no others:

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

Production release manifests are a strict one-archive contract. `SHA256SUMS` must contain exactly one entry, and that entry must name the exact literal `SchneeGlass-X.Y.Z.zip` candidate. Filename matching is not regex-based; a lookalike filename must not satisfy archive membership. The checksum self-check runs only after this exact manifest contract passes.

A checksum proves artifact integrity relative to the manifest; it does **not** replace Apple code signing or notarization.

## Production release gates

A production macOS release must not be published until all of the following are green:

- canonical CI and compatibility CI
- current `main` branch protection is enabled
- Canonical and Compatibility Bootstrap CI jobs are required and source-bound to the GitHub Actions App
- release metadata validation
- AddressSanitizer baseline
- scheduled/manual diagnostics appropriate for the release window
- Developer ID Application signing using credentials stored outside the repository
- Hardened Runtime preserved
- App Sandbox entitlements verified after signing
- optional release entitlements are fail-closed: `network.client` must be positively absent, `get-task-allow=true` is rejected, and ambiguous PlistBuddy probe results are not treated as absence
- required plist values are accepted only after PlistBuddy completes successfully; partial expected output followed by probe failure is rejected
- `codesign --verify --deep --strict` PASS
- signed ZIP bundle metadata matches requested version/build/bundle identity
- `RELEASE_EVIDENCE.txt` schema v1 validation PASS
- candidate workflow exact-name/path/event/branch/success identity validation PASS
- Apple notarization status = `Accepted`
- notarization ticket stapled to the distributed app
- `xcrun stapler validate` PASS
- Gatekeeper assessment PASS
- final SHA-256 artifact manifest
- final install/launch Manual QA on the supported macOS baseline
- repository release immutability enabled
- release governance explicitly reviewed
- public build-number monotonicity validation PASS
- publication workflow revalidation PASS, including the final post-Draft current-`main` freshness check
- final GitHub Release reports `isImmutable=true`
- final immutable GitHub Release has exactly the expected three assets
- final public Release target and remote tag both resolve to the exact candidate source commit

Private keys, certificates, passwords, API keys, and notarization credentials must never be committed to this public repository.

## Credential boundary

Signing/notarization credentials come from the protected `production-release` environment and exist only for the lifetime of the release job.

The production script uses a temporary keychain for imported Developer ID material and removes temporary credential material during job teardown.

Repository files may document secret/variable names and required formats, but must never contain actual credential values or encoded certificate/key material.

See [`docs/RELEASE_CREDENTIALS.md`](docs/RELEASE_CREDENTIALS.md).

## Repository governance boundary

The release workflow now automatically verifies the subset of repository governance available through read-only Metadata APIs:

- current `main` reports `protected=true`
- the Canonical Bootstrap CI job is required
- the macOS 15 Compatibility Bootstrap CI job is required
- both required checks are explicitly bound to the GitHub Actions App

Before first publication, Issue #33 still requires human configuration/review of:

- release immutability enabled
- `main` protection/ruleset configured so the automated required-check gate passes
- unvalidated direct pushes and bypasses to the release source sufficiently restricted
- production environment approval/deployment protection where available

The publication workflow requires `confirm_release_governance=true` after this review. The workflow intentionally fails closed if it cannot read the branch/rules metadata or if either source-bound Bootstrap check is absent. Settings that require repository Administration visibility remain human-attested and are independently checked where possible after publication (for example, the final Release must report `isImmutable=true`).

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
3. configure `main` branch/ruleset so both Bootstrap CI jobs are required from the GitHub Actions App, and review direct-push/bypass governance
4. run the first real Developer ID signed/notarized candidate
5. verify schema v1 signed ZIP evidence, including actual `bundle_build`
6. complete [`docs/MANUAL_QA.md`](docs/MANUAL_QA.md) against that exact candidate
7. run `Publish Production Release` with all confirmations, including release governance
8. verify exact candidate workflow provenance and build-history gate PASS
9. verify the first immutable public v0.1 Release, including exact target/tag provenance, and record its run/tag/checksum/evidence
