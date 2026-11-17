# Authenticated public-release build-history snapshot for ad-hoc candidates

Status: **read-only GitHub history preparation**. This is not an ad-hoc Release publisher, a public-release authorization step, or a proof that main cannot change.

The repository contains a pinned legacy-release manifest. The wrapper obtains the **published Release tag list directly from authenticated GitHub API pagination**, instead of trusting an arbitrary tag list provided by a caller.

## Usage

With GitHub CLI, jq and Python 3 installed and authenticated for read access to `Lamy210/SchneeGlass`:

```bash
gh auth status
bash Scripts/materialize-authenticated-adhoc-release-history.sh /tmp/schneeglass-history-snapshot
```

The output path must not exist. The script stages data in a private temporary directory and only creates the final directory after all source data is accepted. It does not delete or replace earlier snapshots. The final promotion uses the operating system's atomic exclusive rename (`renameatx_np` with `RENAME_EXCL` on macOS; `renameat2` with `RENAME_NOREPLACE` on Linux). An occupied path, including an empty directory, file or symlink created after the last existence check, is rejected. Unsupported operating systems, missing native functions or filesystems without the exclusive rename flag fail closed; ordinary rename/mv is never a fallback. Use a trusted operator-controlled parent on a local filesystem; concurrent hostile modification of its ancestry and network-filesystem crash semantics are outside this contract.

The output contains:

- `release-inventory.json` — original paginated API response, including drafts for auditing.
- `published-tags.txt` — all distinct non-draft public Release tags, including prereleases, sorted deterministically.
- `history/{index}/RELEASE_EVIDENCE.txt` — normalized build evidence from the strict authenticated history consumer, plus release metadata and legacy/notarized metadata when applicable. The new ad-hoc reader validates assets in a private temporary directory without persisting ZIP bytes.

For known legacy tags, the actual tag commit and pinned BUILD_INFO digest are mandatory; added evidence is refused. Other releases must have exactly one recognized evidence schema and immutable=true. New ad-hoc releases use exact-ID asset downloads and the offline validator. Historical notarized releases use the existing strict text evidence verifier and authenticated metadata digest; that format does not independently attest ZIP bytes. Every release and tag is re-read before its normalized record is written. Both paginated inventory reads target github.com explicitly. Before atomic promotion, the complete published tag-to-ID map is re-fetched and compared; a new, missing or replaced published Release fails closed. The final inventory response is retained as release-inventory-final.json. These reads are not a transaction, and publication still requires a fresh preflight. The wrapper refuses malformed pages, repeated Release IDs or public tag names, unsupported public tag syntax, incomplete materialization, and GitHub API failures. It also **requires every tag recorded in the checked-in legacy-public-releases.tsv baseline** (currently v0.1.0 and v0.1.1) to appear in the authenticated non-draft GitHub inventory; a supposedly empty inventory is rejected for SchneeGlass. Private/draft releases are not public build history; their tag collisions must still be rejected separately by the Release slot preflight.

To verify a candidate against this snapshot, use the existing ad-hoc monotonic build adapter:

```bash
bash Scripts/verify-adhoc-candidate-build-history.sh \
  /path/to/candidate-artifact \
  0.2.0 3 \
  0123456789abcdef0123456789abcdef01234567 \
  /tmp/schneeglass-history-snapshot/history
```

The example version, SHA and output directory are placeholders. Pass independently authenticated candidate data, not values copied from untrusted notes.

## Limits / required controls before publishing

- GitHub CLI uses the configured authenticated remote API. The source list is complete **as far as successful CLI pagination for the authenticated caller shows**. Missing access, an unexpected response or unavailable historical evidence fails closed; the fixture suite uses mocked API results rather than production GitHub credentials.
- A successfully materialized snapshot only reflects GitHub's state at the time of collection. Immediately before future tag creation and publication, requery Releases and tags, verify the candidate source against live main, and recheck build history. Otherwise concurrent releases may invalidate the earlier snapshot.
- The snapshot does not reserve a tag, prove a QA reviewer's identity, authorize a Release, or prove real macOS code-signature state. These are independent requirements in [Issue #520](https://github.com/Lamy210/SchneeGlass/issues/520).
- Creating or altering GitHub Releases, modifying existing tags, signing with Developer ID, notarizing via Apple, and disabling Gatekeeper are all outside this script's behavior.
- Releases v0.1.0 and v0.1.1 already exist for this repository. **The script fails closed if either is absent**, including an empty response. A genuinely empty repository is not a supported case for this hardcoded SchneeGlass workflow.

This is a separate, minimal safety primitive to connect to a future human-QA-gated ad-hoc publisher. No published artifact is produced here.
