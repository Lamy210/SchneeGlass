# Ad-hoc public Release evidence: offline validator (R03-01a)

This is a non-publishing primitive, implementing the proposed schema in PR #536. It does not authorize publication, authenticate GitHub API data, or attest real macOS QA.

Run on Linux or macOS with Python 3.9+ and a trusted, stable local directory:

    python3 Scripts/verify-adhoc-public-release-evidence.py <asset-directory> <expected-tag> <expected-source-sha>

The expected tag and actual resolved Git commit must come from an independent authenticated source, not from the evidence itself. Successful stdout is only the canonical positive build string; errors are nonzero with no build on stdout.

Assets: ADHOC_RELEASE_EVIDENCE.json, BUILD_INFO.txt, SHA256SUMS, SchneeGlass-X.Y.Z-adhoc.zip. The evidence must contain exactly the fields defined in the validator (schema_version integer 1; IDs and run_attempt decimal strings; Apple signing claims boolean false). BUILD_INFO uses the existing ten candidate metadata fields with distribution=github-adhoc; source_branch=main; minimum_macos=15.0. SHA256SUMS uses exactly one LF-terminated lowercase hex entry with two spaces and the exact public file name. The public ZIP bytes must hash to the approved inner candidate ZIP digest. The outer Actions artifact digest remains distinct provenance metadata.

Metadata files are bounded to 16 KiB each; the archive is provisionally bounded to 1 GiB and hashed in chunks. Leaf symlinks, special files, missing assets, duplicate/unknown keys, wrong types, wrong IDs, malformed timestamps, mismatched names/build/commit/hashes and mixed legacy evidence fail closed. No ZIP extraction, signature validation, GitHub writes, or network access is performed. Use an operator-controlled directory with no concurrent writers. This is not a defense against adversarial mutation of an entire local directory tree between reads.

Remaining: authenticate historical release/tag/asset identity and immutable status; verify actual owner QA/run/artifact before publication; preserve legacy pins; implement round-trip history validation before a create-only publisher. Old Releases are not migrated or changed. Synthetic fixtures are not real QA.
