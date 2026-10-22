# Ad-hoc Actions candidate artifact provenance

Status: **read-only provenance preflight**. It verifies GitHub Actions artifact identity, not an authorized public Release.

Run from a trusted SchneeGlass checkout with authenticated `gh` and `jq`:

```bash
bash Scripts/verify-adhoc-run-artifact-from-github.sh \
  123456789 \
  0.2.0 \
  0123456789abcdef0123456789abcdef01234567
```

All values above are synthetic examples. The expected source SHA must be independently supplied and must match the live main checked by the existing `verify-adhoc-run-from-github.sh` policy.

## Checks

- Reuse the authenticated run check: exact GitHub repository and pinned candidate workflow, successful manual `workflow_dispatch`, first attempt, exact live `main` commit.
- Independently re-read the requested workflow run and validate expected source commit and repository ID.
- Enumerate **all pages** of the run's Actions artifacts through authenticated `gh api --paginate --slurp`; reject malformed/inconsistent totals, missing pages, duplicate artifact IDs and GitHub API errors.
- Require exactly one named `SchneeGlass-X.Y.Z-adhoc-candidate` artifact from the requested run. Reject missing/duplicate, expired/empty artifacts, absent or malformed SHA-256 digest, wrong run/repository/head repository/branch/source commit.
- Emit its authenticated artifact ID and GitHub **outer Actions artifact ZIP** digest for a later download step.

GitHub's Actions artifact digest is **not** the same as the app archive `SchneeGlass-X.Y.Z-adhoc-candidate.zip` stored inside it. The inner ZIP must separately pass `verify-adhoc-candidate-artifact.sh` and the manual QA record's independently verified archive digest must agree.

A `pull_request` workflow run does not upload a public candidate and will be rejected. Expired artifacts may no longer appear in GitHub's API; an absent artifact is a hard failure, not a reason to select a different run.

## Limitations and publication blockers

This script does **not** download, extract, verify the binary contents, publish, or reserve any GitHub tag. A future publisher must download **by the exact returned artifact ID**, verify the downloaded outer ZIP bytes against the authenticated digest, safely extract it without path traversal/symlink issues, and verify the inner ZIP, actual macOS code signature and File Safety behavior.

The GitHub run, latest main, artifact listing and candidate files are separate mutable views of GitHub state. Revalidate immediately before the eventual create-only public publication step and handle changes/concurrent publication as failures. An authenticated human reviewer must approve the exact candidate SHA and inner archive digest; merely providing a QA text record cannot authenticate a reviewer.

Repository branch protection and immutable Release settings from [Issue #519](https://github.com/Lamy210/SchneeGlass/issues/519) must be configured separately. No Developer ID certificate, Apple notarization, Apple secrets, Gatekeeper bypass or legacy production workflow is used.
