# SchneeGlass Production Release Credential Contract

このドキュメントはDeveloper ID direct distribution用CIへ渡すcredentialの**名前・責務・lifecycle**だけを定義します。

実値、certificate、private key、password、API keyをrepositoryへcommitしてはいけません。

## Protected environment

Production signing / notarization jobはGitHub Environment:

```text
production-release
```

の中でだけ実行します。

Environmentには少なくとも以下を設定し、可能ならrequired reviewer / deployment protection ruleを使用します。

## Secrets

### `DEVELOPER_ID_P12_BASE64`

`Developer ID Application` certificateと対応private keyを含むPKCS#12 (`.p12`) のbase64表現。

- repository fileへ保存しない
- job内のtemporary fileへだけdecodeする
- temporary keychainへimportする
- job終了時にtemporary file/keychainを削除する

### `DEVELOPER_ID_P12_PASSWORD`

上記PKCS#12のimport password。

- logへ出力しない
- command traceを有効化した状態で展開しない

### `APPSTORE_CONNECT_PRIVATE_KEY_BASE64`

Apple notarization用 **Team App Store Connect API key** の`.p8` private keyをbase64化したもの。

SchneeGlassではnotarytool authenticationにTeam API keyを使用する。Individual API keyはnotarytool用途に採用しない。

- job内temporary fileへだけdecodeする
- permissionをowner read-only相当に絞る
- notarization完了/失敗に関係なくjob teardownで削除する

## Environment variables / non-secret identifiers

次は秘密値ではないが、production environmentの設定値として管理する。

### `APPLE_TEAM_ID`

Developer ID certificateを所有するApple Developer Team ID。

### `APPSTORE_CONNECT_KEY_ID`

notarytoolで使用するTeam App Store Connect API key ID。

### `APPSTORE_CONNECT_ISSUER_ID`

Team App Store Connect API key issuer ID。

## Ephemeral values

次はGitHub secretとして長期保存しない。

### Temporary keychain password

release job開始時にrandom生成し、そのjob lifetimeだけ使用する。

### Temporary paths

例:

```text
$RUNNER_TEMP/SchneeGlassRelease.keychain-db
$RUNNER_TEMP/DeveloperID.p12
$RUNNER_TEMP/AuthKey.p8
```

固定home directoryやrepository working treeへcredential materialを書き込まない。

## Temporary keychain lifecycle

Production jobは概ね次の順序を守る。

```text
random keychain password生成
  ↓
temporary keychain作成
  ↓
Developer ID P12 decode
  ↓
certificate/private key import
  ↓
non-interactive codesign用partition list設定
  ↓
Developer ID identityを検証
  ↓
archive/sign
  ↓
署名・entitlement検証
  ↓
notarization / stapling / Gatekeeper
  ↓
always cleanup
```

`security find-identity`で`Developer ID Application` identityが0件または複数で曖昧な場合はReleaseを停止する。

## Notarization authentication

notarytoolは次の形でTeam API keyを使用する想定。

```text
--key <temporary AuthKey.p8>
--key-id <APPSTORE_CONNECT_KEY_ID>
--issuer <APPSTORE_CONNECT_ISSUER_ID>
```

private keyの内容をcommand argumentやlogへ直接展開しない。

## Fail closed

次のどれかが欠ける場合、production jobはunsigned artifactへfallbackしてはいけない。

- Developer ID certificate/private key
- P12 password
- Team ID
- Team App Store Connect API private key
- key ID
- issuer ID

Credential不足時はReleaseを明示的に失敗させる。

Unsigned Release Candidate workflowは別系統として維持し、production signing failureを回避するための代替公開経路にはしない。

## Rotation / compromise

credential漏洩または疑いがある場合:

1. 該当credentialをApple/GitHub側で無効化・rotationする
2. repository historyへ実値が入っていないか確認する
3. release job/log/artifactへcredential materialが混入していないか確認する
4. 必要に応じて既存Developer ID/notarization ticketの影響を評価する
5. 新credentialでproduction pipelineを再検証する

公開済みrelease tag/artifactを同じversionで差し替えない。修正版は新version/buildとして発行する。
