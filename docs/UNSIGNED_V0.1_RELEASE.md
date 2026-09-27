# Unsigned v0.1.0 release policy

The `release/0.1.0` branch exists to publish the first public v0.1.0 build without Apple Developer ID signing or notarization.

This does **not** replace the hardened signed/notarized production release path on `main`. It is a separate bootstrap distribution path intended to make v0.1.0 publicly downloadable while Apple signing remains unconfigured.

Release properties:

- version: `0.1.0`
- build: `1`
- tag: `v0.1.0`
- archive: `SchneeGlass-0.1.0-unsigned.zip`
- Apple Developer ID signed: no
- Apple notarized: no
- SHA-256 manifest: required
- source commit: exact `release/0.1.0` workflow commit
- GitHub Release title must contain `(Unsigned)`

Users must be warned that macOS Gatekeeper can block first launch and that overriding Gatekeeper should only be done when they trust the repository and have verified the checksum.

The signed/notarized release work tracked separately remains valid for a future trusted distribution.
