# SchneeGlass Repository Governance

This document defines the repository-side governance required before a production release can be published.

The release workflows are fail-closed, but they cannot configure GitHub repository administration settings themselves. The canonical configuration is therefore versioned as an importable ruleset recipe and revalidated immediately before publication.

## Canonical main ruleset

Source of truth:

```text
.github/rulesets/main-release-governance.json
```

The recipe targets only:

```text
refs/heads/main
```

Required active rules:

```text
deletion
non_fast_forward
pull_request
required_status_checks
```

Policy intent:

- `main` cannot be deleted.
- force pushes to `main` are prohibited.
- changes to `main` must arrive through a pull request.
- external approval is not required for the solo-maintainer v0.1 workflow (`required_approving_review_count = 0`).
- review conversations must be resolved before merge.
- both Bootstrap CI jobs must pass against the latest target branch state.
- required checks are accepted only from the GitHub Actions App.
- the canonical recipe contains no bypass actors.

Required check contexts:

```text
Canonical / Xcode 26.6 / App Build / Safety Guards
Compatibility / macOS 15 / App Build
```

Expected GitHub Actions integration ID:

```text
15368
```

A same-named check from another App, an unbound classic context, or a ruleset check without the expected `integration_id` is not release authority.

## Applying the ruleset and immutable releases

Repository administration permission is required to create rulesets and enable release immutability. The release workflows intentionally do not request that permission.

### Preferred administrator helper

After this helper has been merged, run it only from a reviewed and up-to-date `main` checkout with an authenticated administrator account:

```bash
git switch main
git pull --ff-only
gh auth status
bash Scripts/setup-release-governance.sh Lamy210/SchneeGlass
```

Prerequisites:

```text
gh
jq
GitHub repository Administration permission
```

The helper is intentionally fail-closed. It:

1. validates the checked-in `.github/rulesets/main-release-governance.json` before any GitHub API mutation and requires its `bypass_actors` field to exist as an empty array;
2. reads the current repository ruleset list;
3. creates the checked-in canonical ruleset only when the repository has zero rulesets;
4. when exactly one ruleset exists and it is the active canonical `SchneeGlass main release governance` ruleset, resumes setup without creating another ruleset;
5. rejects an inactive canonical ruleset, duplicate/layered canonical rulesets, and any differently named pre-existing ruleset before further mutation;
6. fetches the exact canonical ruleset detail by ID and requires an active branch ruleset targeting exactly `refs/heads/main` with no excluded refs;
7. requires live `bypass_actors` to be observable and exactly empty before certifying governance;
8. semantically normalizes the live ruleset detail and the checked-in recipe, then requires the reviewed rule set and parameters to match exactly (ordering differences are ignored, but added/removed rules and parameter drift are rejected);
9. enables or re-enables repository release immutability through the GitHub REST API;
10. re-reads the immutable-release state and requires `enabled=true`;
11. re-reads the live `main` branch and effective active branch rules;
12. runs the same branch/rule/required-check validators used by production publication.

The helper does not configure `production-release` Environment secrets or variables and never handles Apple credential material.

The checked-in ruleset recipe is rejected before any `gh api` call if `bypass_actors` is missing, malformed, or non-empty. This prevents an unsafe recipe drift from being POSTed and only discovered after live mutation.

The setup is not transactional across GitHub APIs. If ruleset creation succeeds but the subsequent release-immutability operation fails, rerunning the normal setup mode is supported only when the live repository contains exactly one active canonical ruleset and no other repository rulesets. In that narrow recovery state the helper does not POST another ruleset; it retries release immutability and then revalidates the complete live governance state. Inactive, duplicate, layered, or differently named rulesets remain fail-closed and require manual review.

### Read-only revalidation

After governance has been applied, use the explicit read-only mode to revalidate the live state without attempting repository mutation:

```bash
bash Scripts/setup-release-governance.sh \
  Lamy210/SchneeGlass \
  --verify-only
```

`--verify-only` performs GET/read operations only. It requires all of the following before reporting success:

```text
exactly one repository ruleset exists
ruleset name = SchneeGlass main release governance
ruleset enforcement = active
ruleset target = branch
ruleset include = refs/heads/main only
ruleset exclude = empty
ruleset bypass_actors = empty
live ruleset semantics = checked-in canonical recipe
repository release immutability enabled = true
main protected = true
deletion rule active
non_fast_forward rule active
pull_request rule active
Canonical Bootstrap CI required from GitHub Actions App 15368
Compatibility Bootstrap CI required from GitHub Actions App 15368
strict required-status-check policy = true
```

The mode fails closed before branch-governance certification when the canonical ruleset is missing, inactive, layered with another repository ruleset, targets anything other than the exact `main` branch contract, contains a bypass actor, or drifts from the checked-in rule semantics. The semantic comparison normalizes unordered lists such as allowed merge methods and required checks while still rejecting added/removed rules or changed reviewed parameters. Repository ruleset enumeration and count extraction must also complete successfully; partial numeric output from a failed `jq` probe is not accepted as proof that exactly one ruleset exists. It also fails closed when the ruleset detail does not expose `bypass_actors`; GitHub only returns that field to callers with ruleset write access, so this administrator-side verification must use sufficiently privileged authentication. It never creates/updates a ruleset and never enables release immutability.

This administrator-side read-only check now proves the canonical ruleset has no bypass actors in addition to the effective branch rules used by production publication. The publication workflow itself intentionally keeps a lower-privilege token and therefore does not substitute for this pre-publication administrator verification or the remaining Environment/repository-setting review described below.

### Manual fallback

If the helper cannot be used, import the checked-in JSON from repository Settings > Rules > Rulesets so the live configuration starts from the reviewed recipe.

For an authenticated repository administrator, the equivalent ruleset create operation is:

```bash
gh api \
  --method POST \
  repos/Lamy210/SchneeGlass/rulesets \
  --input .github/rulesets/main-release-governance.json
```

Do not run the create command repeatedly; it creates another ruleset. If a matching ruleset already exists, review and update that ruleset instead of creating duplicate layered policy accidentally.

Release immutability can be enabled with:

```bash
gh api \
  --method PUT \
  -H 'X-GitHub-Api-Version: 2026-03-10' \
  repos/Lamy210/SchneeGlass/immutable-releases
```

After applying governance, verify the effective branch state:

```bash
gh api repos/Lamy210/SchneeGlass/branches/main --jq '.protected'

gh api --paginate \
  'repos/Lamy210/SchneeGlass/rules/branches/main?per_page=100'
```

Expected high-level state:

```text
main protected = true
active rule types include:
  deletion
  non_fast_forward
  pull_request
  required_status_checks
```

## Automated publication gate

`Publish Production Release` reads the current `main` branch summary and the effective active branch rules immediately before promotion.

Publication requires all of the following:

```text
main protected = true
pull_request rule active
non_fast_forward rule active
deletion rule active
Canonical Bootstrap CI required from GitHub Actions App 15368
Compatibility Bootstrap CI required from GitHub Actions App 15368
```

The validators are:

```text
Scripts/verify-release-branch-protection.sh
Scripts/verify-release-required-branch-rules.sh
Scripts/verify-release-required-checks.sh
```

The active-rules endpoint reports rules that currently apply to `main`. If required rules disappear, become inactive, or no longer target `main`, production publication fails before Release creation.

## Human-attested governance

The read-only publication token can verify effective branch rules but does not replace repository-administration review.

Before setting:

```text
confirm_release_governance = true
```

first run the administrator-side read-only verification from an up-to-date `main` checkout:

```bash
bash Scripts/setup-release-governance.sh \
  Lamy210/SchneeGlass \
  --verify-only
```

This proves that the sole canonical repository ruleset has no bypass actors at the time of the check. Also verify in GitHub Settings:

- no repository/organization policy outside the sole canonical repository ruleset introduces an unintended bypass path;
- `production-release` environment approval/deployment protection is configured as intended;
- repository release immutability is enabled;
- direct-push behavior is actually blocked for the maintainer account in normal operation.

Release immutability is separately attested before publication and then verified again after publication by requiring the resulting GitHub Release to report `isImmutable=true`.

## Change policy

Treat `.github/rulesets/main-release-governance.json` and `Scripts/setup-release-governance.sh` as release-control-plane code.

Changes must go through a pull request and must keep Bootstrap CI plus `Release Governance Setup Tests` green. Do not weaken the live repository rule first and update the recipe afterward.

If the desired governance policy changes:

1. change the checked-in recipe and validators in a reviewable PR;
2. pass Bootstrap CI and Publish Production Release preflight;
3. apply the reviewed change in GitHub Settings or with the administrator helper where its zero-ruleset or sole-active-canonical recovery contract applies;
4. re-read the effective rules for `main` (prefer `--verify-only` once the canonical ruleset exists);
5. keep Issue #33 open until the first signed/notarized immutable v0.1 release is successfully published.
