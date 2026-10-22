# Pre-publication ad-hoc candidate / owner QA validation chain

Status: **non-publishing, fail-closed preflight**. This does **not** authorize or execute a GitHub Release.

The individual validators are already reviewed: exact GitHub run identity and live main (#525); Actions artifact ID and outer digest (#529); safe downloaded outer ZIP extraction (#530); inner app ZIP metadata and checksum (#522); and a previously unedited repository-owner approval comment on Issue #520 (#531).

This script **composes those checks** on one exact candidate, rather than leaving the user to manually copy untrusted hashes between separate commands.

## Invocation

With an independently downloaded Actions artifact ZIP from the exact GitHub artifact ID and an owner-written QA comment on Issue #520:

```bash
bash Scripts/verify-adhoc-candidate-approval-chain.sh \
  123456789 \
  777 \
  0.2.0 \
  3 \
  0123456789abcdef0123456789abcdef01234567 \
  987654321 \
  /path/to/downloaded-actions-artifact.zip \
  /path/to/new-candidate-extraction-directory
```

All values above are **synthetic examples**. The command expects, in order: manually dispatched run ID, exact Actions artifact ID, version, build, source commit SHA, numeric owner QA Issue-comment ID, downloaded outer ZIP file and a **new, nonexisting extraction directory**.

The authenticated API validator reads current GitHub run/main/artifact state and returns the outer ZIP digest. The extractor checks that digest before and after extraction. The inner candidate validator checks its independent ZIP checksum and BUILD_INFO; the QA-comment validator checks the owner-authored approval against the recomputed **inner ZIP digest**. Finally, the script refetches the authenticated run/main/artifact identity to detect changes during preflight.

This command does not select another run or artifact if the requested one is unavailable; it fails closed. The output directory is never overwritten. If a late-stage QA check fails, the new extraction directory may remain for inspection; users can remove it themselves after reviewing the failure.

## Trust boundaries and remaining release blockers

- A passing API/comment check **does not prove that macOS manual QA was actually carried out**. The owner must independently complete the QA checklist on the exact candidate, and only the human owner may post approval.
- The approval check relies on GitHub's author account identity and exact full-body comment. It is not a replacement for device QA logs, approved operating systems, File Safety/recovery verification or code-signature/entitlement verification on actual macOS hardware.
- The *outer* GitHub Actions ZIP digest, *inner* ad-hoc application ZIP digest and SHA of the source commit are distinct values; none can substitute for another.
- The command **does not** enumerate or verify the complete public Release build history, the Release tag slot, repository governance, required CI checks for the publication source, or final Release immutability. The existing history/tag verifiers and Issue #519 policy must be applied in a separate publication-time gate.
- The command also does not fetch/download by ID. The user or trusted downloader must retrieve the exact artifact and preserve its bytes; the authenticated digest check makes a different outer file fail.
- Github state can change after the final API read. A future publisher must recheck all required state immediately before any **create-only**, race-safe tag/Release operation and fail on concurrent change.

No Developer ID signing, notarization, Apple credentials, Gatekeeper bypass, repository settings mutation, release upload or runtime filesystem operation is performed by this command.

Regression fixtures use synthetic GitHub API responses, a synthetic outer ZIP and a synthetic inner archive, **not a real macOS app**, so fixture success must never be interpreted as manual QA approval or distribution readiness.
