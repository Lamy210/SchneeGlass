# SchneeGlass Production Release Credential Contract

このドキュメントはDeveloper ID direct distribution用CIへ渡すcredentialの**名前・形式・責務・lifecycle・運用境界**を定義します。

実値、certificate、private key、password、API keyをrepositoryへcommitしてはいけません。

## Protected environment

Production signing / notarization jobとproduction publication jobはGitHub Environment:

```text
production-release
```

の中でだけ実行します。

GitHubで次の順に設定します。

1. Repository `Settings` > `Environments` を開く
2. `production-release` を作成または選択する
3. `Deployment branches and tags` は `Selected branches and tags` を選ぶ
4. `Branch` ruleとしてexact `main` を追加する
5. 運用可能なら `Required reviewers` を設定する
6. bypassを許可しない方針なら `Allow administrators to bypass configured protection rules` を無効化する
7. 下記Environment secrets / variablesを登録する

`Production Release Candidate`と`Publish Production Release`のcredentialed jobはいずれも`main`からmanual dispatchするため、production environmentへ許可するrefは`main`だけでよい。release tagをdeployment branch/tag ruleへ追加する必要はない。

`Protected branches only`はmain保護がまだ未設定の状態で代替として使わない。repository側のmain rulesetは別途[`docs/REPOSITORY_GOVERNANCE.md`](REPOSITORY_GOVERNANCE.md)に従って設定する。

Environment protection ruleがある場合、そのruleが通過するまでEnvironment secretsはjobから利用できない。

### Required reviewersの注意

別のtrusted reviewerを運用できる場合はrequired reviewerを設定することを推奨する。

solo-maintainer運用で、workflowを起動する本人しかreviewerになれない場合は、本人だけをrequired reviewerにした上で`Prevent self-review`を有効化すると承認できなくなる。独立reviewerを用意できない間は、その設定を無理に有効化せず、`main`限定deployment、明示的workflow confirmation、repository governance、release immutabilityを維持する。

## Secrets

以下は**Environment secrets**として`production-release`に登録する。

### `DEVELOPER_ID_P12_BASE64`

`Developer ID Application` certificateと対応private keyを含むPKCS#12 (`.p12`) のbase64表現。

- repository fileへ保存しない
- job内のtemporary fileへだけdecodeする
- temporary keychainへimportする
- job終了時にtemporary file/keychainを削除する
- base64 decode後が空データの場合はproduction releaseを停止する

macOSで改行なしbase64ファイルを作る例:

```bash
/usr/bin/base64 < DeveloperID.p12 | tr -d '\n' > DeveloperID.p12.base64
```

生成した`.base64`ファイルはGitHub secret登録後に不要なら削除し、repository配下へ置かない。

### `DEVELOPER_ID_P12_PASSWORD`

上記PKCS#12のimport password。

- logへ出力しない
- command traceを有効化した状態で展開しない
- repository / workflow YAMLへliteralで書かない

### `APPSTORE_CONNECT_PRIVATE_KEY_BASE64`

Apple notarization用 **Team App Store Connect API key** の`.p8` private keyをbase64化したもの。

SchneeGlassではnotarytool authenticationにTeam API keyを使用する。Individual API keyはnotarytool用途に採用しない。

- job内temporary fileへだけdecodeする
- permissionをowner read-only相当に絞る
- notarization完了/失敗に関係なくjob teardownで削除する
- base64 decode後が空データの場合はproduction releaseを停止する

macOSで改行なしbase64ファイルを作る例:

```bash
/usr/bin/base64 < AuthKey_XXXXXXXXXX.p8 | tr -d '\n' > AuthKey.p8.base64
```

`.p8`はAppleから再ダウンロードできないため、GitHub secretとは別に安全なcredential保管先で原本を管理する。生成したbase64中間ファイルはrepositoryへcommitしない。

## Environment variables / non-secret identifiers

以下は秘密値ではないが、**Environment variables**として`production-release`に登録する。

### `APPLE_TEAM_ID`

Developer ID certificateを所有するApple Developer Team ID。

SchneeGlassのvalidator contract:

```text
10-character ASCII alphanumeric
```

例示値をrepositoryへ固定せず、Apple Developer accountの実Team IDを設定する。

### `APPSTORE_CONNECT_KEY_ID`

notarytoolで使用する**Team** App Store Connect API key ID。

SchneeGlassのvalidator contract:

```text
10-character ASCII alphanumeric
```

`.p8`と同じTeam API keyのKey IDを指定する。

### `APPSTORE_CONNECT_ISSUER_ID`

Team App Store Connect API key issuer ID。

SchneeGlassのvalidator contract:

```text
UUID: 8-4-4-4-12 hexadecimal
```

Team keyではIssuer IDを使用する。Individual keyへ置き換えない。

## Credential validation layers

Production releaseはcredentialを3層で検証する。

### 1. Encoded input contract

`Scripts/verify-release-credential-inputs.sh`はcredential materialをdecodeする前に次をfail-closed検証する。

```text
RELEASE_VERSION                         present + X.Y.Z
DEVELOPER_ID_P12_BASE64                present + valid non-empty base64
DEVELOPER_ID_P12_PASSWORD              present
APPLE_TEAM_ID                          present + 10-char ASCII alphanumeric
APPSTORE_CONNECT_KEY_ID                present + 10-char ASCII alphanumeric
APPSTORE_CONNECT_ISSUER_ID             present + UUID
APPSTORE_CONNECT_PRIVATE_KEY_BASE64    present + valid non-empty base64
```

この層は「文字列・identifier・base64 envelopeが正しい」ことだけを証明する。base64として正しくても、中身がPKCS#12やprivate keyでなければ次の層で拒否する。

### 2. Decoded credential structure

`Scripts/build-notarized-release.sh`はP12と`.p8`を`$RUNNER_TEMP`へdecodeし、permissionを絞った後、`Scripts/verify-release-decoded-credentials.sh`を実行する。

validatorはOpenSSLを使って次を確認する。

```text
DeveloperID.p12
  - file exists / non-empty
  - supplied P12 passwordでPKCS#12としてparse可能

AuthKey.p8
  - file exists / non-empty
  - private keyとしてparse可能
```

wrong P12 password、valid base64だがPKCS#12ではないpayload、valid base64だがprivate keyではないpayloadはfail-closedする。

この検証は次より**前**に完了する。

- `release-output`作成
- temporary keychain作成
- certificate/private key import
- Apple notarization通信

PR preflightではその場で生成したsynthetic EC key / self-signed certificate / PKCS#12だけを使用する。`production-release` Environment secretsの実値は読み取らず、Appleへ通信しない。

### 3. Real Apple identity / authentication

decoded credential validatorはcredentialの構造を証明するだけであり、次は実credentialed runでのみ証明できる。

- P12内に実際の`Developer ID Application` certificate/private key identityがあること
- temporary keychainへのimportが成功すること
- `Developer ID Application` identityがexactly oneであること
- certificateのTeam IDが`APPLE_TEAM_ID`と一致すること
- `.p8` / Key ID / Issuer IDの組み合わせがApple側の実Team API keyと一致すること
- Apple authenticationが成功すること
- notarization statusが`Accepted`になること

したがってsynthetic fixtureのGREENだけでIssue #33の実credential設定を完了扱いにしない。

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

## Temporary credential / keychain lifecycle

Production jobは概ね次の順序を守る。

```text
encoded credential input contract validation
  ↓
release metadata / credential-free production preflight
  ↓
P12 / p8を$RUNNER_TEMPへdecode + chmod 600
  ↓
decoded PKCS#12 / private-key parse validation
  ↓
release-output初期化
  ↓
temporary keychain作成
  ↓
certificate/private key import
  ↓
non-interactive codesign用partition list設定
  ↓
Developer ID identity / Team IDを検証
  ↓
archive/sign
  ↓
署名・entitlement検証
  ↓
notarization / stapling / Gatekeeper
  ↓
always cleanup
```

validation失敗を含め、decodeされたP12/p8は`EXIT` cleanupで削除する。

`security find-identity`で`Developer ID Application` identityが0件または複数で曖昧な場合はReleaseを停止する。

## Notarization authentication

notarytoolは次の形でTeam API keyを使用する。

```text
--key <temporary AuthKey.p8>
--key-id <APPSTORE_CONNECT_KEY_ID>
--issuer <APPSTORE_CONNECT_ISSUER_ID>
```

private keyの内容をcommand argumentやlogへ直接展開しない。

## Operator readiness checklist

最初のcredentialed run前に、値そのものをIssue/PRへ貼らず次だけを確認する。

- [ ] `production-release` Environmentが存在する
- [ ] deployment branch ruleが`main`だけを許可する
- [ ] required reviewer / self-review / admin bypass方針を決めた
- [ ] 3 Environment secretsを登録した
- [ ] 3 Environment variablesを登録した
- [ ] Team App Store Connect API keyを使用している
- [ ] local base64中間ファイルをrepositoryへ置いていない
- [ ] repository main governance / release immutabilityを別途確認した
- [ ] `.github/workflows/production-release.yml`のcredential-free preflightがgreen
- [ ] synthetic decoded credential fixtureがgreen

実値の存在や正しさはGitHub integrationから読み取れないため、チェックボックスをコード変更だけで完了扱いにしない。

## Fail closed

次のどれかが欠ける、形式不正、decode不能、またはdecode後のcredential structureが不正な場合、production jobはunsigned artifactへfallbackしてはいけない。

- Developer ID certificate/private key payload
- P12 password
- Team ID
- Team App Store Connect API private key
- key ID
- issuer ID

wrong P12 password、非PKCS#12 payload、非private-key payloadもReleaseを明示的に失敗させる。

Unsigned Release Candidate workflowは別系統として維持し、production signing failureを回避するための代替公開経路にはしない。

## Rotation / compromise

credential漏洩または疑いがある場合:

1. 該当credentialをApple/GitHub側で無効化・rotationする
2. repository historyへ実値が入っていないか確認する
3. release job/log/artifactへcredential materialが混入していないか確認する
4. 必要に応じて既存Developer ID/notarization ticketの影響を評価する
5. 新credentialでproduction pipelineを再検証する

公開済みrelease tag/artifactを同じversionで差し替えない。修正版は新version/buildとして発行する。

## References

- GitHub Actions environments: <https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments>
- GitHub deployment environment rules: <https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments>
- Apple App Store Connect API keys: <https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api>
- Apple App Store Connect API setup: <https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api>
