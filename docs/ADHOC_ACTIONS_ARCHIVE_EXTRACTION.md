# Verify and safely extract a downloaded ad-hoc Actions artifact

Status: **offline verification helper only**. No GitHub Release publishing, Apple Developer ID signing or notarization.

A manually dispatched `Ad-Hoc Release Candidate` run uploads an **Actions artifact ZIP** containing six files, one of which is the **inner** `SchneeGlass-X.Y.Z-adhoc-candidate.zip` application archive.

Before processing a downloaded Actions artifact, establish the run and artifact ID/digest using `Scripts/verify-adhoc-run-artifact-from-github.sh` (PR #529). Download by the exact GitHub artifact ID rather than selecting an artifact only by name.

Example with synthetic values:

```bash
python3 Scripts/extract-verified-adhoc-actions-archive.py \
  /path/to/downloaded-actions-artifact.zip \
  sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  0.2.0 \
  /path/to/new-extraction-directory
```

Replace the digest with the **authenticated SHA-256 of the outer Actions ZIP**, and use an output directory that does not exist. The CLI never silently overwrites an existing directory or file.

## What is checked

- Exact outer archive SHA-256, validated before any extraction, from the **same open file descriptor** used to extract.
- Outer archive must be a nonempty regular file, not a symlink, and must satisfy a bounded size.
- Exactly the six expected flat files: the inner candidate ZIP, `BUILD_INFO.txt`, `SHA256SUMS`, `README.txt`, `CODESIGN_DETAILS.txt`, `ENTITLEMENTS.plist`.
- Rejects traversal and absolute paths, duplicate entries, nested paths, ZIP symlinks, directory entries, encrypted members, unsupported compression, empty files, excessive member size and extreme compression ratios.
- Creates only a new output directory, in restrictive mode, and removes its partial contents if extraction fails. Caller must treat nonzero exit as unusable.

This uses the standard-library Python `zipfile` module; it does not change any application runtime dependency or app filesystem behavior.

## Mandatory next checks

1. Run `Scripts/verify-adhoc-candidate-artifact.sh` on the extracted directory using independently authenticated version/build/source SHA. That command verifies the **inner application ZIP SHA-256** and the exact candidate metadata.
2. Run the verified QA evidence / authenticated reviewer check bound to the inner archive's digest. A text file claiming QA passed is **not** enough to establish a human approval.
3. Verify the real macOS application signature and entitlements in a suitable trusted macOS QA environment.
4. Before any future publication, recheck GitHub run identity, live main, exact Actions artifact ID, immutable Release/tag slots, and complete public version/build history.
5. Apply branch protection and immutable GitHub Release governance as required in Issue #519.

This CLI does not fetch from GitHub, authenticate provenance by itself, sign, bypass Gatekeeper, create a tag, or upload any Release asset. The publisher must connect the individually tested controls and revalidate at mutation time. See Issue #520.
