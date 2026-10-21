# Verified GitHub source for ad-hoc candidate runs

The read-only helper `Scripts/verify-adhoc-run-from-github.sh` strengthens the offline candidate metadata validator introduced in #521. It **does not** publish a Release or authenticate a human QA approval.

## Usage

From a trusted checkout after authenticating the GitHub CLI with read access to `Lamy210/SchneeGlass`:

```bash
gh auth status
bash Scripts/verify-adhoc-run-from-github.sh 123456789
```

The number above is a synthetic example; substitute the actual **first-attempt, manually dispatched** `Ad-Hoc Release Candidate` workflow run ID.

The helper fetches, using `gh api`, the GitHub **run resource** and live **`main` branch resource**, and validates:

- exact repository name and matching head-repository identity;
- exact numeric workflow identity `369218665`, name and workflow file path;
- the requested run ID equals the ID of the returned run;
- manual `workflow_dispatch`, `main` branch, completed and successful, first attempt;
- candidate commit is a lowercase non-zero SHA-1 and **equals the latest live main SHA**.

The previous `verify-adhoc-publication-candidate.sh` remains the canonical policy check. `gh` and `jq` must be installed. A read-only GitHub credential is sufficient; no administration, release write, Developer ID, or notarization credential is used. Endpoint failure or malformed results reject the candidate.

## Trust and TOCTOU limitations

1. A user-provided JSON file is not an authenticated GitHub API result. This script never consumes user-provided run JSON; it asks the authenticated `gh` CLI for the run.
2. It confirms the state at the **time of the two API reads**. The live `main` ref could move immediately afterward. A future publisher must repeat the check just before tag creation, upload and publish, and fail if it changes.
3. It does **not** download the candidate or prove that its ZIP is the one uploaded by this run. Candidate artifact digest, actual app signature, approved manual QA and public Release immutability remain separate mandatory checks under [Issue #520](https://github.com/Lamy210/SchneeGlass/issues/520).
4. GitHub API values are authenticated only to the degree that the host and CLI/token configuration are trusted. For release automation, use an appropriately scoped GitHub Actions token or GitHub App, not a pasted response or another repository's result.
5. GitHub's numeric `workflow_id` is deliberately pinned. If the existing workflow is replaced and GitHub assigns a different ID, revise the pinned identity only in a separately reviewed PR after verifying it against GitHub, not by disabling the check.

This helper does not require Developer ID signing or Apple notarization, does not bypass Gatekeeper, and does not make an ad-hoc candidate safe for immediate public distribution by itself.
