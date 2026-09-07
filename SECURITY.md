# SchneeGlass Security Policy

SchneeGlassはユーザーのFileを扱うため、利便性よりFilesystem Safetyを優先します。

## 1. Public Repository

このRepositoryはPublicです。

Commitしてはいけません:

- API key
- Access token
- Private key
- Certificate private material
- `.env`
- Notarization credential
- Security-scoped bookmark raw data
- private diagnostics export
- 実在する会社・顧客の内部データ
- 個人/会社環境を示すTest Fixture

`.gitignore`だけをSecurity Boundaryとして信用しません。

`Scripts/verify-public-repo.sh`をCIで実行し、credential-like tracked fileと高確度Secret Patternを検出します。

このGuardはGitHub側のSecret Scanning等を置き換えるものではなく、Repository内の追加防御です。

## 2. Test / Sample Data

Test dataは架空値のみ使用します。

良い例:

```text
ExampleProject
sample.txt
/tmp/SchneeGlassTests/<UUID>/
```

禁止:

```text
実在会社名
顧客名
社内Repository名
社内Server名
実際のHome Directory Path
```

## 3. v0.1 Entitlement Baseline

予定する最小Entitlement:

```text
com.apple.security.app-sandbox = true
com.apple.security.files.user-selected.read-write = true
```

`App/SchneeGlass.entitlements`をBaselineとします。

v0.1では以下を追加しません:

```text
network.client
不要なApple Events
Full Disk Access相当の要求
Accessibility Permission要求
```

Entitlement追加はArchitecture/Security Review対象です。

## 4. Filesystem Mutation Boundary

v0.1ではuser-owned sourceについて以下を禁止します。

```text
Move
Rename
Delete
Replace
Truncate
Write
```

Copy destinationへのmutationは `SchneeGlassFileSystemAdapter` 内に限定します。

Glass-owned staging fileのfinal commit Renameのみ、将来 `InternalStagingCommitter` へ限定して許可します。

`Scripts/verify-file-safety.sh` がallowlist外のmutation APIをCIで検出します。

## 5. Security-Scoped Access

Folder accessはSecurity-Scoped Bookmarkを使用します。

原則:

```text
resolve
→ startAccessing
→ use
→ stopAccessing
```

Acquire/Releaseを必ずbalanceします。

Bookmark raw dataをLog/Issue/Test Fixtureへ出してはいけません。

## 6. Unknown Data Policy

SchneeGlassが所有していると証明できないFileを自動変更しません。

特に:

```text
.glass-* のような名前
```

だけを根拠にDelete/Renameしてはいけません。

Recovery cleanupにはSchneeGlassのOperation Metadataとの一致が必要です。

## 7. Logging Privacy

Public Logへ出してよい情報:

```text
operation category
item count
duration
generic error category
```

Defaultで出してはいけない情報:

```text
absolute path
filename
folder name
repository name
company/customer name
bookmark data
```

OSLog privacy機構を利用します。

## 8. Network / Telemetry

v0.1:

```text
Cloud backend   = none
Telemetry       = none
Runtime AI      = none
Account         = none
Network need    = none
```

Updater等でNetworkを導入する場合、別ADRでNetwork Boundaryを定義します。

## 9. Dependency Security

Runtime dependency追加には `DEPENDENCIES.md` 更新が必要です。

確認項目:

- maintainer activity
- license
- Swift compatibility
- transitive dependency
- security-sensitive codeへの侵入範囲
- removal strategy

## 10. Release Security

Public stable binaryは最終的に以下を満たす必要があります。

```text
Developer ID signed
Hardened Runtime
Notarized
Stapled
Entitlement verified
Smoke tested
```

Developer IDが利用できない場合、unsigned binaryをtrusted stable releaseとして扱いません。

## 11. Security Incident

Public issueへSecretそのものを貼り付けてはいけません。

Secret漏洩を発見した場合は、値を再掲せず以下を優先します。

```text
credential revoke / rotate
history exposure assessment
affected release assessment
preventive guard update
```
