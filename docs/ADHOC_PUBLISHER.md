# Create-only ad-hoc Publisher (draft implementation)

Dependencies: #543 strict complete history, #545 public asset preparation, #546 read-back, #519 governance. Do not merge/dispatch until all dependencies are integrated, exact-main integration tests pass, and the repository owner has reviewed the permission and failure model.

The proposed workflow is owner-dispatched, main-only, first attempt only, pinned to the candidate/current main. Fixed repository-wide concurrency group serializes this workflow across versions (not external manual operations). No automatic release on pull_request or push. Explicit confirmation PUBLISH vX.Y.Z plus authenticated manual owner QA; no simulated approval.

## Credential separation and runtime attestation

The workflow contains **two distinct jobs** under the same fixed concurrency group and owner-only first-attempt dispatch:

1. `governance` receives only `SCHNEEGLASS_RELEASE_GOVERNANCE_TOKEN`, runs `Scripts/setup-release-governance.sh Lamy210/SchneeGlass --verify-only` on a clean exact-live-`main` checkout, and emits only the attested source commit SHA after all canonical rules, empty bypass actors, required checks and repository-wide immutability are verified. It never creates, updates or deletes GitHub settings or a Release.
2. `publish` runs **only after governance succeeds**, receives only `SCHNEEGLASS_RELEASE_OWNER_TOKEN`, and rejects an absent/mismatched `SCHNEEGLASS_GOVERNANCE_ATTESTED_SHA`, incorrect GitHub job context or changed candidate SHA. It repeats exact-live-main, effective branch protection, required CI and immutable-release checks with the narrower credential before the first write and at final pre-publication verification.

**Owner-managed prerequisites (not provisioned by this PR):**

| Secret | Only exposed to | Permissions to verify before provisioning |
| --- | --- | --- |
| `SCHNEEGLASS_RELEASE_GOVERNANCE_TOKEN` | `governance` job | Repository-limited owner credential with the actual ability to read canonical ruleset `bypass_actors` (GitHub documents that this field requires ruleset write access, commonly Administration write). Check expiry/rotation; no published assets, tag mutations or release upload in this job |
| `SCHNEEGLASS_RELEASE_OWNER_TOKEN` | `publish` job | Different, repository-limited owner credential: Actions read for the exact run/artifact; Contents write for create-only tag/Release/assets; Administration **read** for immutable-release state; read access to effective branch rules. No Administration write in this job |

**Do not reuse the same elevated PAT for both secrets.** Job separation reduces exposure of the high-privilege credential during archive preparation, upload and publication, but does **not** make that credential harmless, create a cryptographic proof of unmodified GitHub settings, or provide a global lock. An administrator can still change governance after the first job. The publishing job re-reads effective protections but cannot independently re-read hidden `bypass_actors` with its narrower token; operator exclusivity, account-level audit and last-minute admin verification remain important.

These are **repository secret names, not configured secrets or proof of permissions**. No GitHub Environment protection or required-reviewer setting is configured by this PR. The owner must explicitly decide whether to introduce a protected environment and environment-scoped publication secret; merely naming an Environment in YAML does not prove it has approval rules. Do not place token values in PRs, logs, command arguments or public artifacts.

The workflow's `GITHUB_TOKEN` remains `contents: read` for both jobs; it is not a substitute for either owner credential. A missing credential, unreadable bypass actors, incomplete ruleset, missing attested SHA, wrong execution context or failed immutable-release GET blocks publication *before* any tag/release writes. Separate job checks are read-only, and no false QA approval is generated.



Sequence:
1. First require the separate successful high-privilege **read-only governance job** for the same workflow and SHA. In the publish job verify exact workflow context, matching attested SHA, owner credential, canonical repository, clean exact-main checkout, effective branch protections, repository-wide immutable releases, and both required CI checks for the exact SHA, explicitly bound to GitHub Actions App 15368 (latest check-run filter, stable total_count on every page, exact unique run count, reject duplicate or missing required name).
2. Download exact candidate artifact ID; prepare four verified public assets and bind approved QA.
3. Repeat candidate, owner QA, complete history, governance and empty tag/Release slot checks.
4. POST create-only lightweight tag at exact SHA. POST draft release, capture ID from that response only. Existing ref collision fails; never adopt previously created resources.
5. Before **each** upload, require the run-owned Draft to contain exactly the previously captured upload IDs, names, sizes, SHA-256 digests and completed upload states; reject missing, foreign or replaced assets before another mutation. Upload the four prepared assets to the captured Draft ID on fixed uploads.github.com, require HTTP 201 and response ID/name/digest/size. No redirects or write retries. Read back the complete Draft against prepared bytes.
6. Repeat authenticated run/QA/history/governance and slot/read-back verification. The owned slot requires exactly one matching draft ID and its tag still at the exact commit.
7. Re-read final draft asset metadata and match every captured upload ID, digest and size. PATCH only that draft ID, then read back published immutable state and all exact bytes. Re-check published asset IDs, digests and sizes against the original upload responses; same-byte replacement with different IDs is not certified. Success is only emitted after published read-back and identity verification.

GitHub writes are not transactional. External mutations may race after the last check; owner must not operate other publisher paths concurrently. A successful CREATE followed by a lost response leaves unknown remote state; a tag may exist without a draft; asset upload failure may leave starter assets; publish may succeed before read-back fails. Stop with stage, tag, captured ID if available, observed upload IDs. Do not delete, overwrite, silently retry, take over an existing draft, or certify an unverified live Release. Operator reconciliation is necessary; no tag or Release is deleted by the publisher. GitHub Actions concurrency serializes only cooperating workflow jobs. It does not prove a global API lock. Cancellation/runner failure may prevent local logging, so use workflow log and GitHub release/tag inspection.

References: https://docs.github.com/en/rest/git/refs#create-a-reference ; https://docs.github.com/en/rest/releases/releases#create-a-release ; https://docs.github.com/en/rest/releases/assets#upload-a-release-asset ; https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency .


## Owner review checklist (blocking, not a CI fixture)

The code in this Draft PR **must not be merged or dispatched** until the repository owner explicitly accepts these decisions. A passing fixture is not an approval. Record the decision on the PR, without including credentials, user paths, or user data:

- **Live governance:** use a clean checkout at exact live main, then run `bash Scripts/setup-release-governance.sh Lamy210/SchneeGlass --verify-only`. Verify the unique canonical ruleset, empty bypass actors, strict required Canonical / Compatibility checks from GitHub Actions App 15368, `main.protected=true` and repository-wide immutable Releases enabled. The file in `.github/rulesets/` is not proof that GitHub settings were applied.
- **Credential review:** separately provision only the reviewed `SCHNEEGLASS_RELEASE_GOVERNANCE_TOKEN` (ruleset-write visibility; governance job only) and a different `SCHNEEGLASS_RELEASE_OWNER_TOKEN` (Actions read / Contents write / Administration read; publish job only) after identifying the exact repository scope, expiry/rotation/revocation plan, and confirmation that each token can access its required GET endpoints. Never silently grant Administration write to the publisher to bypass a failed Ruleset probe; review and stop instead.
- **Human QA:** on an exact-main first-attempt manually dispatched ad-hoc candidate, independently record the run ID, artifact ID, source SHA, outer Actions ZIP digest and actual inner application ZIP digest. Perform real macOS 15/26 install, Gatekeeper, Sandbox/entitlements, File Safety, Recovery and upgrade checks. Only the authenticated owner may personally post the exact unedited approval comment on Issue #520, bound to the **inner ZIP digest**. A bot/fixture must never post it.
- **Operational exclusivity:** the workflow's concurrency group serializes **only this workflow**. The owner must ensure no other publisher, human or automation changes the proposed tag or Release while this process runs.
- **Create-only failure policy:** accept that GitHub tag creation, Draft creation, asset upload and publication cannot be rolled back atomically. Never retry blindly, delete a remotely created tag/draft/asset, overwrite an asset or adopt an existing draft from another run. First reconcile with remote state, then decide on independently reviewed remediation.

### Read-only reconciliation after a partial or ambiguous result

The failure log prints `stage`, `tag`, captured `release_id` (if available), `active_asset` (the filename being checked or uploaded, otherwise `none`), and `uploaded_asset_ids` as deterministic `filename:asset_id` pairs (or `none`). These names come only from the verified four-file public asset set; no credential, filesystem path or file content is included. An interrupted `active_asset` has **unknown remote upload outcome** even when its ID was not captured. Cancellation and connection loss can occur *before* the script prints any of these fields. Absence of a printed ID is **not** proof that the corresponding GitHub write failed.

| Failed/ambiguous stage | What may already exist | Safe operator action |
| --- | --- | --- |
| `create-tag` | Ref may have been created even when its response was lost | Inspect the exact Git ref and owner-only activity; **do not re-POST** the tag |
| `create-draft` | Tag may exist with no Draft, or Draft may exist but its ID was not captured | Inspect all matching Releases, including Drafts; never discover one by tag and silently adopt it |
| `upload` | One or more valid assets may exist; a server-side upload can succeed without a received response | Inspect the captured Draft ID and enumerate its assets/IDs/digests; do not reupload or delete |
| `draft-readback` / `final-preflight` | A complete Draft may exist, but QA/main/history/governance may have changed | Leave the Draft untouched and document the changed prerequisite |
| `publish` / `published-readback` | Release may already be public or may be mutable/unverified | Inspect exact Release ID, tag target and asset IDs/digests; **do not issue a second PATCH** |

Use authenticated **read-only** probes with a trusted operator account. The following are inspection examples (substitute an observed tag/ID; never use samples as mutation targets):

```bash
gh api 'repos/Lamy210/SchneeGlass/git/ref/tags/vX.Y.Z'
gh api --paginate 'repos/Lamy210/SchneeGlass/releases?per_page=100'
gh api 'repos/Lamy210/SchneeGlass/releases/<observed-positive-release-id>'
gh api --paginate 'repos/Lamy210/SchneeGlass/releases/<observed-positive-release-id>/assets?per_page=100'
```

A `404` for one probe does not establish that all endpoints are empty, and a failed authorization/network response is **not** evidence of absence. Annotated tags must resolve to their actual commit before comparing source identity. A Release reporting `immutable=false` must not be certified. All remediation requires explicit owner decision; an abandoned tag/Release must not be deleted or reused by this publisher.

The review record should identify the observed commit, candidate run/artifact/ZIP digests, governance verification, actual QA decision, workflow run/attempt, write stage, observed tag/Release/asset IDs, and unresolved ambiguity **without disclosing the token or personal filesystem data**.

Fixtures exercise the production orchestration against synthetic assets and mock GitHub. Regression cases include a foreign upload appearing after the second asset, wrong remote asset IDs/names/sizes/digests/state, fixed upload host, redirect rejection and duplicate created IDs; in every negative case the publisher stops without subsequent publication. No actual token, owner QA, API write, or public release is performed in CI. Live draft/upload/post-publication semantics and permissions remain unverified. The integrated suite uses the actual preparer's output, fresh checks, real build comparator, and actual read-back against mock GitHub transport; the strict authenticated history acquisition fixture runs in the same workflow. The normalized history snapshot boundary in the fresh-check tests is synthetic. Before readiness: require the integrated suite and dependency PRs to pass, review GitHub API/timeout and workflow guards, establish governance and real owner QA.
