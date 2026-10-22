# GitHub-authenticated owner QA approval for an ad-hoc candidate

Status: **read-only candidate approval record verifier**. This helper does not perform manual QA, sign anything, publish a Release, or grant permission to bypass Gatekeeper.

## Trust model

The offline QA evidence checker (PR #524) checks consistency between a supplied text record and an inner archive SHA-256, but the local text record is not sufficient to establish who approved the candidate.

This helper fetches both the SchneeGlass repository identity and an exact GitHub Issue comment by **numeric ID**, through authenticated GitHub CLI read API. It requires the record to be a previously **unmodified** comment on Issue #520 authored by the actual GitHub owner account: repository ID 1359347782, owner user ID 90091196, login Lamy210, author association OWNER and human-account type User. Other identities, bot comments, edited comments and generic progress reports fail closed.

No QA comment is automatically created. **The authorized owner must personally perform the manual QA and post the specific record**. A model or CI process must not generate an approval on the owner's behalf.

## Exact comment body

After verifying the candidate on a trusted macOS installation, the owner may create the following exact plain-text Issue #520 comment, replacing all synthetic values with actual verified values:

    SCHNEEGLASS_ADHOC_QA_APPROVAL_V1
    run_id=123456789
    run_attempt=1
    source_sha=0123456789abcdef0123456789abcdef01234567
    version=0.2.0
    build=3
    archive_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    qa_result=pass

The archive_sha256 is the **inner application ZIP** digest recomputed from the actual candidate, **not** the outer GitHub Actions artifact ZIP digest. No Markdown fence, prefix, suffix, duplicate or extra field is accepted. The GitHub authenticated comment creation timestamp is used; a self-asserted reviewer name or timestamp inside the body is not trusted.

With gh and jq available, check an exact comment ID:

    bash Scripts/verify-adhoc-qa-comment-from-github.sh \
      987654321 123456789 0.2.0 3 \
      0123456789abcdef0123456789abcdef01234567 \
      aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

All identifiers above are synthetic. The script checks the repository and comment's GitHub-returned owner identities and the expected candidate values.

## Remaining release requirements

- An owner-authored structured comment **still does not prove that real human macOS QA occurred**, or that the owner credentials could not have been used by automation. It is an authenticated publication decision record, not physical evidence of testing. The human must confirm the installation, Gatekeeper first-launch behavior, File Safety/recovery, codesign and entitlements against the exact candidate.
- Verify the candidate run identity and current main from GitHub independently. Verify the exact Actions artifact ID and outer ZIP digest; safely extract, verify the inner archive and bind its independently recomputed checksum to this record. This helper only checks independently supplied expected values, not the ZIP itself.
- Before any future create-only publication, recheck this comment (it may be deleted or edited), run/main state, successful CI, complete public build history, existing Git tags/Releases, and authenticated owner approval.
- Because the repository is user-owned, this first version intentionally permits **only the personal repository owner**. Do not automatically expand it to collaborators, bots or CI accounts. Any new release authority policy needs a separate reviewed change.
- Branch protection, release immutability and administrative governance from Issue #519 must be established before publishing. If those permissions are not available, do not publish.
- The helper uses no Developer ID signing key, Apple notarization, Gatekeeper bypass, production-release environment or GitHub mutation.

See Issue #520 for release acceptance criteria. This is one verification primitive, not the final release authorization or publisher.
