# Create-only ad-hoc Publisher (draft implementation)

Dependencies: #543 strict complete history, #545 public asset preparation, #546 read-back, #519 governance. Do not merge/dispatch until all dependencies are integrated, exact-main integration tests pass, and the repository owner has reviewed the permission and failure model.

The proposed workflow is owner-dispatched, main-only, first attempt only, pinned to the candidate/current main. Fixed repository-wide concurrency group serializes this workflow across versions (not external manual operations). No automatic release on pull_request or push. Explicit confirmation PUBLISH vX.Y.Z plus authenticated manual owner QA; no simulated approval.

The job requires an independently configured owner credential with sufficient repository permissions for Actions read, contents write, administration reads and canonical ruleset detail. The repository's existing setup --verify-only validates live ruleset, local exact main and immutability; the publisher independently checks enabled=true. The secret is an unconfigured prerequisite, not created by this PR. Never log or place tokens in curl command arguments. The owner must explicitly choose/provision a suitably scoped credential and avoid external concurrent mutations; update permissions only after review. The GitHub Actions GITHUB_TOKEN is not a substitute for administration/owner authority. Missing/malformed credentials fail closed.

Sequence:
1. Verify exact workflow context, owner token, canonical repository, governance, clean exact-main checkout, and both required CI checks for the exact SHA, explicitly bound to GitHub Actions App 15368 (latest check-run filter, reject duplicate or missing required name).
2. Download exact candidate artifact ID; prepare four verified public assets and bind approved QA.
3. Repeat candidate, owner QA, complete history, governance and empty tag/Release slot checks.
4. POST create-only lightweight tag at exact SHA. POST draft release, capture ID from that response only. Existing ref collision fails; never adopt previously created resources.
5. Upload four assets by captured ID on fixed uploads.github.com, require status 201 and response ID/name/digest/size. No redirects or write retries. Read back draft against prepared bytes.
6. Repeat authenticated run/QA/history/governance and slot/read-back verification. The owned slot requires exactly one matching draft ID and its tag still at the exact commit.
7. Re-read final draft asset metadata and match every captured upload ID, digest and size. PATCH only that draft ID, then read back published immutable state and all exact bytes. Success is only emitted after published read-back.

GitHub writes are not transactional. External mutations may race after the last check; owner must not operate other publisher paths concurrently. A successful CREATE followed by a lost response leaves unknown remote state; a tag may exist without a draft; asset upload failure may leave starter assets; publish may succeed before read-back fails. Stop with stage, tag, captured ID if available, observed upload IDs. Do not delete, overwrite, silently retry, take over an existing draft, or certify an unverified live Release. Operator reconciliation is necessary; no tag or Release is deleted by the publisher. GitHub Actions concurrency serializes only cooperating workflow jobs. It does not prove a global API lock. Cancellation/runner failure may prevent local logging, so use workflow log and GitHub release/tag inspection.

References: https://docs.github.com/en/rest/git/refs#create-a-reference ; https://docs.github.com/en/rest/releases/releases#create-a-release ; https://docs.github.com/en/rest/releases/assets#upload-a-release-asset ; https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency .

Fixtures exercise the production orchestration against synthetic assets and mock GitHub. No actual token, owner QA, API write, or public release is performed in CI. Live draft/upload/post-publication semantics and permissions remain unverified. Before readiness: run integrated fixture with actual preparer and consumer, review GitHub API/timeout and workflow guards, establish governance and real owner QA.
