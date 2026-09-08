# ADR-0006: v0.1 は Developer ID による直接配布とする

- Status: Accepted
- Scope: v0.1

## Context

SchneeGlass は macOS 専用のネイティブユーティリティであり、v0.1 では GitHub 上の公開RepositoryとRelease Pipelineを配布基盤として整備している。

現時点のアプリは以下を満たす。

- macOS 15+
- App Sandbox有効
- Hardened Runtime有効
- Mac App Store固有サービスへの依存なし
- GitHub Actions上でunsigned Release Candidateを再現可能
- Release metadata / Sandbox baseline / SHA-256 integrity validationを実装済み

AppleはMac App Store外のmacOSアプリについてDeveloper IDによる署名とnotarizationを提供している。custom CIでは`xcrun notarytool`でnotary serviceへ提出でき、notarization ticketは`xcrun stapler`で配布物へstapleできる。

## Decision

SchneeGlass v0.1 のproduction distributionは **Developer IDによるMac App Store外の直接配布** とする。

配布経路は次を基本とする。

```text
main
  ↓ validated version metadata
Release build
  ↓
Developer ID Application signing
  ↓
codesign verification
  ↓
ZIP packaging
  ↓
Apple notarization (notarytool)
  ↓
stapling + validation
  ↓
Gatekeeper assessment
  ↓
SHA-256 manifest
  ↓
immutable GitHub Release
```

### Required production gates

公開可能なartifactはすべて次を満たすこと。

- `Developer ID Application` identityで署名済み
- Hardened Runtime有効
- App Sandbox entitlement維持
- `codesign --verify --deep --strict` PASS
- Apple notarization ACCEPTED
- notarization ticket staple済み
- `xcrun stapler validate` PASS
- Gatekeeper assessment PASS
- release versionとGit tag一致
- SHA-256 integrity manifest生成済み
- manual smoke QA PASS

### Credential boundary

Signing / notarization credentialはRepositoryへ保存しない。

CIではprotected release environmentから一時的に注入し、job終了時に破棄する。

Repository内に許可するのはcredentialの**名前・契約・取得方法の説明だけ**であり、次はcommit禁止とする。

- `.p12` / certificate private key
- certificate password
- App Store Connect / Notary API private key
- issuer ID等を含むprivate credential bundle
- temporary keychain

### App Sandbox

Developer ID直接配布ではApp Sandboxは必須条件ではないが、SchneeGlassでは既存のfilesystem security boundaryを維持するため **App Sandboxを継続する**。

Sandboxを外す変更はv0.1 release作業の一部として扱わず、別ADRを必須とする。

### Artifact policy

- unsigned CI artifactはverification専用
- notarization前artifactをpublic production releaseへ昇格しない
- 公開済みtag/artifactは置換しない
- bad releaseは新しいversion/buildで再発行する

## Alternatives Considered

### Mac App Store

v0.1では採用しない。

理由:

- 現在のGitHub中心の配布/開発フローと直接配布が自然に整合する
- App Store固有サービスを利用していない
- v0.1でApp Review / Store metadata / App Store release automationを追加するとRelease scopeが大きくなる

将来Mac App Storeへ追加配布すること自体は否定しない。必要になった時点で別ADRで判断する。

### Unsigned distribution

productionでは不採用。

CI/debug用途のunsigned artifactは維持するが、end-user向けtrusted releaseとして公開しない。

## Consequences

### Positive

- GitHub Release中心の既存フローを活かせる
- Apple標準のGatekeeper / Developer ID / notarization trust chainを利用できる
- Store固有機能やApp Reviewをv0.1必須要件にしなくてよい
- Sandbox + Hardened Runtimeを維持できる

### Negative

- Developer ID certificateとnotarization credentialの安全なCI管理が必要
- 配布・更新・rollbackはSchneeGlass側で管理する必要がある
- App Storeによる自動更新/ホスティングは利用できない

## Follow-up

TASK-018では以下を実装する。

1. protected release environment / secret contract
2. temporary keychainへのDeveloper ID certificate import
3. signed Release build verification
4. `notarytool` submission + accepted-state verification
5. `stapler` staple / validate
6. Gatekeeper assessment
7. immutable GitHub Release publication
8. signed artifact manual QA checklist
