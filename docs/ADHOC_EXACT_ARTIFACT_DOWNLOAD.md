# Exact GitHub Actions artifact download — authenticated and no-overwrite

Status: **download/verification helper for temporary testing artifacts**; not a GitHub Release publisher.

The manually dispatched `Ad-Hoc Release Candidate` workflow creates a short-lived Actions artifact ZIP. Choosing the latest artifact, or downloading by name only, could select a different workflow run. The previously merged `verify-adhoc-run-artifact-from-github.sh` binds the run, its exact artifact ID, source SHA and outer ZIP checksum to authenticated GitHub API results. This command uses that exact ID for download.

## Usage

After authenticating the GitHub CLI for **Actions: read** access to `Lamy210/SchneeGlass` (plus `jq` and `shasum` for the existing verifiers):

```bash
bash Scripts/download-verified-adhoc-actions-artifact.sh \
  123456789 \
  777 \
  0.2.0 \
  0123456789abcdef0123456789abcdef01234567 \
  /path/to/new-actions-candidate.zip
```

All identifiers are synthetic placeholders. The output path must not exist and its parent must be a real directory. `gh api` downloads the binary from GitHub's exact `/actions/artifacts/{artifact_id}/zip` endpoint. The endpoint redirects to an expiring download URL; the CLI follows it. GitHub's returned *outer Actions ZIP* digest is verified against the file's SHA-256.

A private file is staged on the destination filesystem. The command refuses an empty or oversized (greater than 1 GiB) download, failed request, changed GitHub run/main or artifact digest on the second verification, and any occupied destination. Only after successful verification does it create a **new hard link** to the staged file, rather than overwriting an existing file with `mv -f`. Failed attempts remove their private stage, not any pre-existing user file.

## Continue the checks

Use the downloaded file with the already merged `verify-adhoc-candidate-approval-chain.sh` or `verify-adhoc-publication-preflight.sh`. The secure extractor separately verifies the outer ZIP checksum before and after extraction, then validates the **inner application ZIP** and metadata. It also checks the owner-authored QA comment against the *inner* ZIP SHA-256.

This downloader does not authenticate manual macOS QA, validate the real binary signature, reserve a tag, create a Release or make the archive public. An authenticated approval comment is not by itself evidence that QA was physically performed. Before any public distribution, the strict repository governance, actual macOS QA, complete public version/build history, create-only race protection and read-back remain mandatory (Issues #519 and #520).

No Developer ID signing, Apple notarization, Apple account secrets, Gatekeeper disabling or legacy production workflow is involved.
