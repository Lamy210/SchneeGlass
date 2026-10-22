# Revalidate the downloaded ad-hoc-signed macOS application

Status: **read-only macOS verification helper**. This script is not an installer, Gatekeeper bypass, notarizer or GitHub Release publisher.

The ad-hoc candidate builder verifies the application during packaging. That is not a substitute for checking the **actual app downloaded and extracted for manual QA**. The helper `Scripts/verify-extracted-adhoc-app.sh` verifies the received `SchneeGlass.app` directly.

## Usage (trusted macOS host)

After selecting an authenticated candidate run, verifying the outer Actions ZIP, verifying the inner app ZIP and unpacking it in a disposable QA directory using normal macOS tools:

```bash
bash Scripts/verify-extracted-adhoc-app.sh \
  /path/to/qa/SchneeGlass.app \
  0.2.0 \
  3
```

The version/build above are examples. Supply independently verified expected values from the exact candidate's build metadata. Do not run this against irreplaceable user files or an arbitrary app obtained from an untrusted source.

The helper is **read-only with respect to the app**. It refuses symlinked app roots, symlinked/missing/empty `Info.plist` or executables, and invalid version/build inputs. It checks:

- `codesign --verify --deep --strict --verbose=2` on the extracted bundle.
- Live `codesign -dv --verbose=4` details: `Signature=adhoc`, absence of Apple certificate `Authority=`, and Hardened Runtime flag.
- Actual `Contents/Info.plist`: expected bundle ID `io.github.lamy210.schneeglass`, version, build and single-instance policy.
- Actual `codesign -d --entitlements :-` output: App Sandbox enabled, user-selected read/write permission enabled, unexpected network client permission absent, and no debug `get-task-allow=true`.

The tests mock macOS programs on an Ubuntu CI runner to exercise failure handling; **those mocked tests do not verify an actual macOS app**. Operators must run the helper against the genuine extracted candidate on macOS, and also exercise Menu Bar, filesystem source safety, copy-only Drop/Recovery and Gatekeeper behavior in the manual QA checklist.

## Security boundaries

This does not authenticate the GitHub run/ZIP by itself: first perform the independently verified download and checksum chain. This does not validate Apple notarization or Developer ID certificates (both intentionally unused). A successful `codesign` validation is not proof that macOS Gatekeeper accepted an unnotarized ad-hoc candidate or that every UI/safety flow was tested.

The script never modifies source folders, removes quarantine, weakens sandbox/entitlements, signs/re-signs the app, deletes app files or invokes GitHub publication. Repository governance and publication-time collision/history/concurrency/asset checks remain required by Issues #519 and #520.
