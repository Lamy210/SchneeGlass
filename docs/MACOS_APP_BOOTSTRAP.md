# SchneeGlass macOS App Bootstrap

このドキュメントは、SchneeGlassのmacOS App TargetとCI build baselineを定義する。

## App Target

- Project: `SchneeGlass.xcodeproj`
- Scheme: `SchneeGlass`
- Deployment Target: macOS 15.0
- Swift Language Mode: Swift 6
- App Sandbox: enabled
- Hardened Runtime: enabled
- Local package: `Packages/SchneeGlassKit`
- Bundle Identifier: `io.github.lamy210.schneeglass`

## CI Build Matrix

### Canonical

- `macos-26`
- Xcode 26.6
- Swift Package tests
- Public Repository Guard
- Architecture Guard
- File Safety Guard
- Debug `.app` build
- Release `.app` build
- generated Info.plist validation
- entitlement source validation
- unsigned Release `.app` artifact upload

### Compatibility

- `macos-15`
- Swift Package tests
- Debug `.app` build

## Signing

CI buildでは `CODE_SIGNING_ALLOWED=NO` を使用する。

CI artifactは**ビルド可能性確認用のunsigned artifact**であり、一般配布用releaseではない。

一般配布では別Release Pipelineで以下を必須とする。

1. Developer ID Application signing
2. Hardened Runtime
3. Notarization
4. Stapling
5. final entitlement verification

## Safety

Public repositoryには以下をcommitしない。

- Developer ID private key
- `.p12` / `.p8`
- notarization credential
- App Store Connect API secret
- provisioning private material

Signing credentialは将来GitHub Secrets等の適切なsecret storeから注入する。
