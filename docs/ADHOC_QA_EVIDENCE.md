# Ad-hoc QA evidence contract (pre-publication guard)

Status: **verification helper only**. This is not a publishing process or an authorization system.

The [ad-hoc release ADR](adr/0011-adhoc-distribution-without-developer-id.md) rejects Developer ID signing and Apple notarization. An Actions candidate is a temporary testing artifact, never an automatically approved public Release.

## The QA record

The offline validator `Scripts/verify-adhoc-qa-evidence.sh` requires a UTF-8 text file with exactly these ten unique, non-empty `key=value` entries (order immaterial):

```text
schema_version=1
candidate_run_id=123456789
candidate_run_attempt=1
candidate_source_commit=0123456789abcdef0123456789abcdef01234567
candidate_version=0.2.0
candidate_build=3
candidate_archive_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
qa_result=pass
reviewed_by=example-reviewer
reviewed_at=2026-10-22T06:00:00Z
```

The source, run ID, reviewer, version and build above are **synthetic examples**. The SHA-256 must be the **actual** digest of the candidate archive, not a copied placeholder. A successful manual QA review must cover the exact candidate, Gatekeeper behavior, supported OS versions, File Safety, recovery, and installation.

Run the offline check only with values independently retrieved from trusted sources:

```bash
bash Scripts/verify-adhoc-qa-evidence.sh \
  /path/to/downloaded-ad-hoc-candidate \
  /path/to/QA_EVIDENCE.txt \
  0.2.0 3 \
  0123456789abcdef0123456789abcdef01234567 \
  123456789 example-reviewer
```

This verifies the candidate's strict `BUILD_INFO.txt` fields and `SHA256SUMS`, then compares the actual archive SHA-256 against the QA record. It also checks the declared run ID, first-run attempt, source commit, version, build, review result, reviewer login and timestamp format.

## Trust boundary and release blockers

**A text file can claim `qa_result=pass` and `reviewed_by=example-reviewer` without the reviewer having approved anything.** The validator only checks *consistency with trusted caller inputs*, not identity authentication or human approval. In particular:

- The eventual publisher must retrieve workflow run identity and latest `main` directly from GitHub, not accept user-provided run metadata.
- Human approval must be sourced from an **authenticated, access-controlled GitHub review/check or equivalent trusted approval record**, and must explicitly bind to the exact candidate run SHA and archive digest.
- The reviewer identity supplied to this helper must be independently authenticated; never infer authorization from the `reviewed_by` field itself. Review timestamps are syntax checked, not a guarantee of chronology.
- The published Release must separately enforce version/build history, tag uniqueness, repository rules, checksum assets, concurrency, and read-back. None of these controls are implemented by this offline validator.
- Do **not** use an ad-hoc Actions candidate or QA text file to bypass Apple Gatekeeper, to claim Apple trust, or to invoke the legacy Developer ID/production workflow.

This helper does not upload or publish any artifact, use credentials, or change application filesystem permissions. See [Issue #520](https://github.com/Lamy210/SchneeGlass/issues/520) for remaining release-gate work.
