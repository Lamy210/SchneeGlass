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

## Applying the ruleset

Repository administration permission is required to create or update rulesets. The release workflow intentionally does not request that permission.

Preferred setup is to import the checked-in JSON from repository Settings > Rules > Rulesets so the live configuration starts from the reviewed recipe.

For an authenticated repository administrator, the equivalent GitHub CLI create operation is:

```bash
gh api \
  --method POST \
  repos/Lamy210/SchneeGlass/rulesets \
  --input .github/rulesets/main-release-governance.json
```

Do not run the create command repeatedly; it creates another ruleset. If a matching ruleset already exists, review and update that ruleset instead of creating duplicate layered policy accidentally.

After applying the rule, verify the effective branch state:

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

Treat `.github/rulesets/main-release-governance.json` as release-control-plane code.

Changes must go through a pull request and must keep the credential-free publication preflight green. Do not weaken the live repository rule first and update the recipe afterward.

If the desired governance policy changes:

1. change the checked-in recipe and validators in a reviewable PR;
2. pass Bootstrap CI and Publish Production Release preflight;
3. apply the reviewed change in GitHub Settings;
4. re-read the effective rules for `main`;
5. keep Issue #33 open until the first signed/notarized immutable v0.1 release is successfully published.
