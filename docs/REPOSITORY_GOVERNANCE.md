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

1. reads the current repository ruleset list;
2. creates `.github/rulesets/main-release-governance.json` only when the repository has zero rulesets;
3. refuses to create a duplicate when `SchneeGlass main release governance` already exists;
4. refuses automatic mutation when any differently named ruleset already exists, requiring manual policy review first;
5. enables repository release immutability through the GitHub REST API;
6. re-reads the immutable-release state and requires `enabled=true`;
7. re-reads the live `main` branch and effective active branch rules;
8. runs the same branch/rule/required-check validators used by production publication.

The helper does not configure `production-release` Environment secrets or variables and never handles Apple credential material.

The setup is not transactional across GitHub APIs. If a later operation fails after an earlier mutation succeeded, do **not** blindly rerun the script. Re-read the live repository settings first. A newly-created canonical ruleset intentionally causes subsequent runs to stop rather than create a duplicate.

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

also verify in GitHub Settings:

- the applied ruleset has no unintended bypass actors;
- no overlapping ruleset introduces an unintended bypass policy;
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
3. apply the reviewed change in GitHub Settings or with the administrator helper where its zero-ruleset safety contract applies;
4. re-read the effective rules for `main`;
5. keep Issue #33 open until the first signed/notarized immutable v0.1 release is successfully published.
