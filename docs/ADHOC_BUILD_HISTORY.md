# Ad-hoc candidate: monotonic public build-history gate

Status: **offline, read-only safety check**. This is neither a public Release publisher nor proof that historical GitHub data was retrieved completely.

Developer ID signing and Apple notarization are not used by this workflow ([ADR-0011](adr/0011-adhoc-distribution-without-developer-id.md)).

## Purpose

macOS application build numbers (`CFBundleVersion`) must not reuse a previously published build number, even when a future Release has a new, unused Git tag. The repository already provides `Scripts/verify-release-build-history.sh` to check monotonic `bundle_build` values. The ad-hoc adapter reuses that tested policy, rather than writing a second history comparison implementation.

Usage, using a candidate and a **complete, independently authenticated and verified** history snapshot:

```bash
bash Scripts/verify-adhoc-candidate-build-history.sh \
  /path/to/verified-candidate-artifact \
  0.2.0 \
  3 \
  0123456789abcdef0123456789abcdef01234567 \
  /path/to/complete-published-build-history
```

The archive directory must include the candidate ZIP, `BUILD_INFO.txt`, `SHA256SUMS`, signature details, entitlements and README. The adapter:

1. Rejects an invalid build input (positive decimal with at most nine digits), missing/symlinked history root or any symlink inside the history.
2. Calls the existing ad-hoc artifact verifier for exact version/build/source SHA, unnotarized ad-hoc metadata and the candidate ZIP's checksum.
3. Converts the **caller-trusted, already-verified build** into a temporary `RELEASE_EVIDENCE.txt` record (`schema_version=1`, `bundle_build=N`).
4. Calls `Scripts/verify-release-build-history.sh` against the materialized public history. The candidate build must be strictly greater than the maximum published build.

An empty history directory is accepted as a *first-publication* case **only when the caller has independently established that no public Releases exist**. For SchneeGlass, historical Releases v0.1.0 and v0.1.1 already exist, so an empty history is not trustworthy.

## Provenance and TOCTOU limitations

- The adapter **does not retrieve** public Release history from GitHub; it cannot tell whether the supplied history snapshot omitted Releases. The future publisher must enumerate *all* non-draft public Releases, materialize/verify each record using `Scripts/materialize-public-release-build-history.sh`, and ensure its source list is complete. A missing or unverifiable release must fail closed.
- Draft and reserved tag conflicts are separate and checked by the read-only Release slot preflight (PR #526). This adapter does not reserve a tag or exclude concurrent publishing.
- Re-fetch the complete public history and rerun all checks immediately before a future create-only tag/Release action. The history and main reference may change between checks.
- A monotonically increasing build does **not** authenticate manual QA, validate an Apple signature, prove archive provenance or establish repository governance. The exact-run, ZIP digest, reviewer authorization and main protection gates under [Issue #520](https://github.com/Lamy210/SchneeGlass/issues/520) remain mandatory.
- The adapter's temporary evidence record is **not** a production `RELEASE_EVIDENCE.txt` asset, and it cannot be substituted for the legacy Developer ID notarization publication evidence format.

The fixtures test higher/equal/lower historical builds, candidate mismatch/tampering, malformed history, symlink rejection, safe arithmetic bounds and the empty-history case.
