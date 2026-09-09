# Installing SchneeGlass

SchneeGlass v0.1 is designed for **Developer ID direct distribution outside the Mac App Store**.

This document applies to a signed, notarized, stapled production Release published through the repository's production release workflow. An unsigned CI artifact is not an end-user production release.

## Supported baseline

- macOS 15 or later
- Apple notarization / Gatekeeper validation must succeed for the production artifact
- App Sandbox remains enabled

## 1. Download the production Release

From the GitHub Release for the desired version, download:

```text
SchneeGlass-X.Y.Z.zip
SHA256SUMS
RELEASE_EVIDENCE.txt
```

Do not use an artifact named `unsigned` as a trusted production build.

## 2. Verify SHA-256

Place the ZIP and `SHA256SUMS` in the same directory, then run:

```bash
shasum -a 256 -c SHA256SUMS
```

Expected result:

```text
SchneeGlass-X.Y.Z.zip: OK
```

If verification fails, do not open or install that archive. Download the Release assets again and confirm that all files came from the same immutable Release.

## 3. Install

1. Open `SchneeGlass-X.Y.Z.zip`.
2. Move `SchneeGlass.app` to `/Applications` or another normal application location you control.
3. Launch SchneeGlass normally from Finder, Spotlight, or Launchpad.

The production Release is expected to be Developer ID signed, notarized, stapled, and accepted by Gatekeeper. SchneeGlass does not require Accessibility permission for its global shortcut feature.

## 4. First launch

On first launch:

1. Confirm the Menu Bar item appears.
2. Open Settings if needed.
3. Add a Glass by choosing a folder through the system folder picker.
4. Grant only the folder access you intend to use.

Folder access uses macOS security-scoped user selection. SchneeGlass should not ask for broad filesystem or Accessibility access merely to operate the v0.1 feature set.

## 5. File-safety expectations

SchneeGlass v0.1 is intentionally non-destructive toward user-owned source files.

```text
Source Move      = not permitted
Source Rename    = not permitted
Source Delete    = not permitted
Silent overwrite = not permitted
```

Regular-file Drag & Drop into a Glass is a **copy** operation. Recovery may operate on app-owned staging files only when ownership evidence is sufficient.

If behavior appears to violate these rules, stop using that build and report the candidate/release version, commit SHA if known, and reproduction steps.

## 6. Gatekeeper or launch failure

A normal production Release should launch without bypassing macOS security controls.

If macOS reports that the app cannot be verified, is damaged, or is blocked:

- do not disable Gatekeeper globally
- do not remove quarantine attributes as a workaround
- verify `SHA256SUMS` again
- confirm you downloaded the asset from the intended immutable GitHub Release
- confirm the Release evidence identifies notarization as accepted
- report the failing macOS version and Release version

Production QA treats Gatekeeper failure as a Release blocker.

## 7. Updating

v0.1 does not rely on replacing an existing immutable Release artifact in place.

For a newer version:

1. download the newer immutable Release
2. verify its SHA-256 manifest
3. quit the currently running SchneeGlass instance
4. replace the application bundle with the newer version
5. launch and confirm existing Glass configuration restores correctly

A bad published Release is corrected by a new version/build, not by silently replacing assets under the same tag.

## 8. Uninstalling

To remove the application, quit SchneeGlass and remove `SchneeGlass.app` from your application location.

SchneeGlass does not own the folders you connected. Removing the app must not delete, move, or rename the user-owned files contained in those folders.

Configuration/recovery metadata is app state rather than user file content. Do not manually delete recovery metadata while investigating an incomplete copy unless the recovery state is understood.

## Release verification reference

Production Release requirements are defined in:

- [`../RELEASE.md`](../RELEASE.md)
- [`MANUAL_QA.md`](MANUAL_QA.md)
- [`RELEASE_CREDENTIALS.md`](RELEASE_CREDENTIALS.md)

The first public v0.1 Release remains blocked until the production credential/governance validation tracked in Issue #33 is complete.
