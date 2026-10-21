# Installing SchneeGlass

SchneeGlass is a native macOS 15+ desktop app. **The project does not use Apple Developer ID signing or Apple notarization for future distribution** ([ADR-0011](adr/0011-adhoc-distribution-without-developer-id.md)). An ad-hoc signature is **not** an Apple-verified developer identity; macOS Gatekeeper may block first launch.

## Available downloads

The currently published ad-hoc GitHub Release is [v0.1.1](https://github.com/Lamy210/SchneeGlass/releases/tag/v0.1.1). Its assets are:

```text
SchneeGlass-0.1.1-adhoc.zip
SHA256SUMS
BUILD_INFO.txt
```

v0.2.0 / build 3 is currently a development/candidate line, **not a published v0.2.0 Release**. The manually dispatched `Ad-Hoc Release Candidate` workflow can produce a short-lived Actions artifact for testing only; it does not automatically publish a Release.

Never treat an `unsigned` artifact or `adhoc-candidate` artifact as a notarized production release.

## 1. Verify a downloaded release

Download the ZIP, `SHA256SUMS`, and `BUILD_INFO.txt` from the **same** trusted GitHub Release page. Check the source tag, release notes, `source_commit`, version, and distribution metadata.

From the directory containing the downloaded assets:

```bash
shasum -a 256 -c SHA256SUMS
```

For v0.1.1 the expected ZIP entry is:

```text
SchneeGlass-0.1.1-adhoc.zip: OK
```

If validation fails, **do not launch** the archive. Re-download from the intended release and investigate. A checksum does not by itself establish the authenticity of an untrusted download source.

## 2. Install and launch

1. Unzip the verified archive and locate `SchneeGlass.app`.
2. Move the app to `/Applications` or another normal application location you control.
3. Open it from Finder.
4. If macOS blocks it because it is not notarized, **do not globally disable Gatekeeper or remove quarantine attributes**. Only if you have independently verified and trust the source, use macOS **System Settings → Privacy & Security → Open Anyway** for this specific app, following the confirmation UI. macOS behavior varies by version and policy; some managed Macs may prohibit bypass.
5. Once started, confirm the Menu Bar item appears and open Settings to add a Glass through the macOS folder picker.

Never grant Full Disk Access or Accessibility permissions simply to bypass an installation failure. Folder access should remain limited to the locations you choose.

## 3. File safety

SchneeGlass must preserve its non-destructive contract:

```text
User-owned source Move      = 0
User-owned source Rename    = 0
User-owned source Delete    = 0
Silent overwrite            = 0
Unknown partial auto-delete = 0
```

Drag & Drop copies supported regular files using the existing safe staging and recovery flow. If this contract appears violated, stop using that build and report its version, source commit, macOS version, and reproduction details.

## 4. Updates and uninstall

For an update, download a **new** version/build from the trusted source and verify its SHA-256 manifest. Quit the previous instance before replacing `SchneeGlass.app`; on relaunch confirm the connected Glass configuration recovers.

Never overwrite an existing published tag/asset silently to replace a broken release. Publish a corrected version/build instead.

To uninstall, quit the app and delete its application bundle. SchneeGlass does not own your connected folders. Avoid deleting configuration or pending-copy recovery metadata until any incomplete copy has been understood.

## 5. Developer ID notes (historical only)

The repository retains documentation and CI for a former Developer ID/notarization-based production design. Those **are not the current project's distribution requirements** and should not be invoked to publish an ad-hoc build. See [ADR-0011](adr/0011-adhoc-distribution-without-developer-id.md), [RELEASE.md](../RELEASE.md), and [Manual QA](MANUAL_QA.md).

Before any future v0.2 ad-hoc GitHub Release is published, the project still needs a separately reviewed release-provenance/QA process. The existing ad-hoc candidate workflow alone is not that public release process.
