# Local verified ad-hoc public asset preparation

This command is read-only with respect to GitHub. It requires the same authenticated preflight as the future publisher; it does not create an approval, tag, draft Release, or public Release.

    python3 Scripts/prepare-verified-adhoc-public-assets.py <run-id> <artifact-id> <version> <build> <source-sha> <owner-qa-comment-id> <downloaded-actions-zip> <new-output-directory>

Use an operator-controlled stable local filesystem and trusted checkout. Python 3.9+ and the existing preflight prerequisites are required. The output directory must not exist. No public output is promoted until preflight, actual-byte QA/digest/governance/slot rechecks, strict offline validation, and a native exclusive directory rename succeed. A private stage contains candidate/history/public assets and is cleaned after success or handled failure. Process crash may leave a private stage; never publish directly from one.

Contents: inner ZIP unchanged under the public name, public BUILD_INFO with distribution=github-adhoc, new LF-terminated SHA256SUMS, ADHOC_RELEASE_EVIDENCE.json. Only authenticated owner comment verifier output supplies the QA timestamp; the actual copied ZIP is hashed and compared through that verifier. No fabricated Apple signing or notarization. The final artifact report binds the actual outer ZIP digest and selected artifact ID. All four assets are verified by the existing offline validator.

This is preparation, NOT publication authorization or a transactional GitHub snapshot. Require integration of the strict full history consumer (#543) before actual publisher work. Repeat fresh preflight, exact-main/governance/slot and owner QA checks at mutation time; verify immutable release and assets after publication. The synthetic unit tests replace external gate scripts in an isolated checkout and exercise the real producer and offline validator; they are not real owner QA.
