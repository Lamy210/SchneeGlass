# Authenticated immutable ad-hoc public Release reader

This is one read-only history primitive for R03-01b. It does not publish, modify tags/settings, or replace the full release inventory consumer.

From a trusted checkout with Python 3.9+ and authenticated GitHub CLI:

    python3 Scripts/verify-authenticated-adhoc-public-release.py <release-id> <tag>

Specify the numeric release ID and tag from a complete authenticated release inventory. On success stdout is one normalized build number. Failures are nonzero with no build output.

The reader checks canonical repository identity, release ID, exact tag, published and immutable flags; requires the four exact assets defined by the new ad-hoc schema; resolves the actual Git ref (including bounded annotated-tag traversal); downloads by exact asset ID with authenticated size/digest and a streaming limit; invokes the offline evidence validator; and rechecks asset identity and resolved tag. It does not accept a caller-supplied URL, trust target_commitish, or require an expired Actions artifact to remain downloadable. It uses a private temporary directory removed on success or failure. API errors and missing digests fail closed. The operator owns GitHub authentication and the trusted checkout. The API reads are not a transactional snapshot; future publication must recheck the complete inventory and governance.

Legacy pinned releases are refused by this reader and require the existing pinned BUILD_INFO checks. New immutable releases with old notarized evidence must be dispatched separately; a mixed or extra asset set is rejected here. This reader alone does not replace full historical enumeration, enforce legacy pin priority in the existing materializer, verify human QA, or authorize publication.

The test suite uses synthetic immutable releases and a mock gh with actual file bytes, the offline validator, and shared monotonic comparator. Real new immutable ad-hoc releases do not yet exist.
