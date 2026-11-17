# Ad-hoc publisher read-back (read-only)

This helper is part of the future publisher; it does not create/update a tag, Release, approval, or settings. It assumes GitHub CLI is authenticated and the local prepared assets and checkout are trusted and stable.

    python3 Scripts/verify-adhoc-release-readback.py draft <prepared-directory> <release-id> <tag> <source-sha>
    python3 Scripts/verify-adhoc-release-readback.py published <prepared-directory> <release-id> <tag> <source-sha>

Both modes require the actual tag already resolves to the independently verified source commit. The future publisher must use create-only tag creation and stop on collision. The draft phase requires draft=true, immutable=false; the published phase requires draft=false, immutable=true; both require prerelease=false. Exact four prepared asset names and size/digest, authenticated Release ID/asset IDs and actual downloaded bytes must agree. The complete downloaded set is checked by the existing offline validator. Re-read the remote state, actual tag and local asset digests before success. A syntactically valid but different evidence file is not accepted.

Official GitHub references:
- https://docs.github.com/en/rest/releases/releases
- https://docs.github.com/en/rest/repos/repos#check-if-immutable-releases-are-enabled-for-a-repository

Before the first mutation the future publisher must verify repository immutability is enabled via GET repos/.../immutable-releases (Administration read access). The current main governance verifier only checks branch protection/rules; it is not sufficient on its own. Failure to read or confirm enabled=true blocks publication. The existing setup-release-governance.sh --verify-only already checks the setting; actual admin setup remains #519.

After uploading to the exact draft ID, run draft read-back and fresh owner QA / exact-main / governance / public-history checks (the final slot check must recognize only the exact owned draft and tag, not accept arbitrary existing releases). Then publish only that draft ID and run published read-back. On timeout or partial failure, stop and report the observed/unknown IDs and state; no overwriting, deletion, automatic adoption, or retry of a non-idempotent mutation. Read-back does not eliminate races, and API-level success is not evidence of real application QA.

Fixtures use the existing mock authenticated release reader, actual ZIP bytes and validators. No authenticated real Release mutation or live draft read-back is performed.
