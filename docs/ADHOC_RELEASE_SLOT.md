# Ad-hoc public Release tag-collision preflight

Status: **read-only, standalone safety preflight** — not a publisher and not proof that publishing is authorized.

The command below checks whether a proposed ad-hoc Release tag is unoccupied **at the time of the check**:

```bash
gh auth status
bash Scripts/verify-adhoc-release-slot.sh v0.2.0
```

It calls authenticated `gh api --paginate --slurp` to examine **all visible GitHub Releases** (including drafts) and existing matching Git tag refs in `Lamy210/SchneeGlass`. It fails if either inventory contains the exact target tag, an endpoint cannot be reached, or the inventory schema is malformed. It does **not** delete or rewrite any old tag/Release.

A GitHub Release may exist without an associated Git tag and a lightweight or annotated tag may exist without a Release. Both inventories are necessary. The check accepts an empty inventory only when it is a successfully fetched array of pages.

## What this does not prove

- **No concurrency guarantee:** another actor can create the tag immediately after this check. A future publisher must recheck just before publication, create the tag using a no-overwrite operation, and fail closed on an already-existing tag. It must not force-update or delete tags on failure.
- **No authorization:** a free tag does not establish that manual QA is approved, the candidate ZIP matches its run, or the reviewer's GitHub identity is authenticated. Those gates remain in Issue #520.
- **No version/build history guarantee:** a new unused tag could still contain a reused or regressed build number. The repository already has `Scripts/materialize-public-release-build-history.sh` and `Scripts/verify-release-build-history.sh`, which a future ad-hoc publisher must apply using the authoritative *complete* publication history and the exact candidate's build.
- **No immutability guarantee:** repository-level GitHub Release immutability and strict main protection must be applied and verified separately via Issue #519.
- **No Apple identity claim:** ad-hoc signed archives are not Apple Developer ID signed or notarized. The script uses only read access to GitHub and does not involve Apple credentials.

The script never creates a GitHub Release, uploads assets, changes tags or modifies repository policy. Its read-only behavior and malformed/duplicate/occupied inventory rejection are covered by a separate Ubuntu CI fixture.
