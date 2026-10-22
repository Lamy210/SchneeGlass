# Ad-hoc publication preflight — read-only, not a publisher

This command composes the independently tested safety guards introduced in SchneeGlass PRs #521–#532. It performs **no GitHub Release write or tag creation**. It cannot be used as proof that the actual macOS QA checklist has been completed or to bypass Apple's Gatekeeper.

## Inputs

From a trusted checkout, with `gh` authenticated to `Lamy210/SchneeGlass`, `jq`, `python3`, `bash` and `shasum` available:

```bash
bash Scripts/verify-adhoc-publication-preflight.sh \
  123456789 777 0.2.0 3 \
  0123456789abcdef0123456789abcdef01234567 \
  987654321 \
  /path/to/downloaded-actions-zip \
  /path/to/new-candidate-directory \
  /path/to/new-history-directory
```

The example IDs, version and SHA are fictitious. Input is, in order: workflow run ID; exact GitHub Actions artifact ID; version; build; source commit SHA; authentic owner QA comment ID; previously downloaded **outer** Actions ZIP; a new directory for the verified candidate files; and a new directory for the authenticated published build-history snapshot.

Both output directories must be absent before execution. On a late failure, **the newly generated evidence may remain for inspection**; it is not automatically removed because unexpected deletion is an unacceptable File Safety behavior.

## Validation sequence

1. Verify that **current** `main` has canonical GitHub protections and both required status checks, via existing `verify-current-release-governance.sh`. The currently unprotected `main` will therefore fail closed until Issue #519 is resolved.
2. Verify the authenticated first-attempt candidate run, live `main`, exact Actions artifact ID and outer ZIP digest. Safely extract six allowlisted files, check the independent inner app ZIP SHA-256/metadata, and match the **unedited repository-owner QA approval comment** to the candidate's actual inner ZIP digest.
3. Acquire and materialize **all visible published GitHub Releases**, including the mandatory known v0.1.0/v0.1.1 baseline. Reject unavailable or unverifiable entries.
4. Check that the candidate build number is strictly higher than previously published builds.
5. Reject a target tag already occupied by a GitHub Release/draft or existing Git ref.
6. Recheck repository governance, live candidate run, source commit and artifact ID/digest. Compare the outer ZIP bytes again against authenticated Actions artifact metadata.

Any failure aborts. The command never automatically chooses a different run, artifact, build, tag, QA approval or destination.

## What is still **not** implemented

- The final independent macOS installation, real `codesign`/entitlements, Gatekeeper and user-file safety QA cannot be replaced by these mocked integration fixtures.
- The exact owner comment establishes GitHub account identity and an explicit approval record, but cannot itself establish that a human performed every QA step.
- GitHub Release **repository-level immutability** must be verified and enabled by an authorized administrator. Branch protection/rulesets must be configured under Issue #519.
- These are separate GitHub API reads. They reduce but cannot eliminate time-of-check/time-of-use races. A future publisher must independently revalidate immediately before **create-only** tag/release writes, enforce concurrency and fail on collision, and verify published assets by read-back.
- No Developer ID certificate, Apple notarization, App Store key, production-signing workflow, global Gatekeeper bypass, public Release upload or tag change is used.

A successful result explicitly says **NOT publication authorization**. Before treating any ad-hoc archive as publicly distributable, apply the remaining Release governance, manual QA and publication-time safeguards from [Issue #520](https://github.com/Lamy210/SchneeGlass/issues/520).
