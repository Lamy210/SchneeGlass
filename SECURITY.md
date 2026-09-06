# Security Policy

## 1. Security Model

SchneeGlass はローカルファイルを扱うため、File Safety を Security Requirement と同等に扱います。

v0.1 の原則:

- App Sandbox enabled
- User-selected file/folder access only
- Full Disk Access 不要
- Accessibility permission 不要
- Network Client entitlement なし
- Runtime AI / telemetry / cloud upload なし
- Silent overwrite なし
- User-owned source Move / Rename / Delete / Replace なし

## 2. Public Repository: 絶対に Commit しないもの

この Repository は Public です。次を Git に追加しないでください。

- API key / access token / refresh token
- Password / secret / private key
- `.p12`, `.p8`, private certificate material
- Notarization credentials
- Provisioning/signing credentials を含む export
- 実在する勤務先・顧客の内部パス
- 実在顧客名や非公開 Project 名を含む fixtures
- 個人メールアドレスや電話番号を含む test data
- Security-scoped bookmark の raw data
- ローカル machine 固有の absolute path
- `.env` や secret-bearing configuration

公開ドキュメント・Issue・PR・CI log にも同じルールを適用します。

## 3. Sample / Test Data

必ず架空値を使用します。

推奨例:

```text
ExampleProject
sample.txt
Example User
/tmp/SchneeGlassTests/<UUID>/
```

実在の会社名・顧客名・repo名を fixture として使いません。

## 4. Logging Privacy

Public diagnostic/log へ以下を出してはいけません。

- Full path
- Filename
- Folder name
- Repository name
- File contents

許可する情報:

- operation category
- generic error category
- duration
- item count
- app/macOS version
- valid/stale bookmark count

Sensitive values が必要な OSLog interpolation は private 扱いとします。

## 5. File Mutation Boundary

Filesystem mutation は `SchneeGlassFileSystemAdapter` 内の allowlisted implementation に限定します。

User-owned source を次へ渡すことは禁止します。

```text
removeItem
moveItem
replaceItem
```

内部 commit rename は、現在の operation が作成し recovery metadata が存在する staging file のみ許可します。

## 6. Unknown Data Policy

SchneeGlass が ownership を証明できない file は自動変更しません。

特に `.glass-*` に似た名前でも recovery metadata がなければ user data とみなし、自動 Delete / Rename を禁止します。

## 7. Dependency Security

Runtime dependency 追加時は次を確認します。

1. Apple API で代替できないか
2. Maintenance 状況
3. Swift 6 compatibility
4. License
5. Transitive dependency
6. Security history
7. Removal strategy
8. SPM support

`DEPENDENCIES.md` の更新なしに runtime dependency を追加しません。

## 8. Reporting a Vulnerability

Repository が初期 Bootstrap 段階のため正式な private vulnerability reporting channel は今後設定します。

公開 Issue に secret・credential・private file content を投稿しないでください。
