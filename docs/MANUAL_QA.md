# SchneeGlass v0.1 Manual QA Checklist

このチェックリストは、CIでは完全に代替できない実ユーザー操作と配布artifactの最終確認用です。

## Release判定

以下の原則を1つでも満たせない場合、そのbuildはRelease不可です。

- user-owned source file loss = 0
- silent overwrite = 0
- user-owned Move / Rename / Delete = 0
- unknown / ambiguous partial fileの自動削除 = 0
- connected folder外への意図しないmutation = 0
- Recovery操作によるfinal user-visible fileの削除 = 0
- App Sandbox / Hardened Runtimeを維持
- candidate provenance / evidence / checksumを証明できる
- public build numberを再利用・巻き戻ししない

QAは使い捨てのtest folderで行い、実業務folderや唯一の原本を使用しないこと。

## 0. Candidate identification

- [ ] 対象Production Release Candidate run IDを記録した
- [ ] workflow nameが`Production Release Candidate`である
- [ ] workflow pathが`.github/workflows/production-release.yml`である
- [ ] eventが`workflow_dispatch`である
- [ ] branchが`main`である
- [ ] workflow status=`completed` / conclusion=`success`である
- [ ] workflow `run_attempt=1`である
- [ ] QA対象runに対して`Re-run jobs`を実行していない。再生成が必要なら新しい`workflow_dispatch` runを作る
- [ ] 対象workflow head commit SHAを記録した
- [ ] `MARKETING_VERSION`を記録した
- [ ] `CURRENT_PROJECT_VERSION`を記録した
- [ ] 対象artifact名を記録した
- [ ] `SHA256SUMS`が存在する
- [ ] `shasum -a 256 -c SHA256SUMS` がPASSする
- [ ] `RELEASE_EVIDENCE.txt`が存在する
- [ ] `schema_version=1`である
- [ ] 以下のkeyが各exactly 1件存在する
  - [ ] `schema_version`
  - [ ] `version`
  - [ ] `notarization_id`
  - [ ] `notarization_status`
  - [ ] `codesign`
  - [ ] `stapler`
  - [ ] `gatekeeper`
  - [ ] `bundle_identifier`
  - [ ] `bundle_version`
  - [ ] `bundle_build`
  - [ ] `commit_sha`
- [ ] unknown key / blank line / malformed lineがない
- [ ] evidenceの`commit_sha`が対象production workflow head SHAと一致する
- [ ] evidenceの`bundle_identifier`が`io.github.lamy210.schneeglass`である
- [ ] evidenceの`bundle_version`がQA対象versionと一致する
- [ ] evidenceの`bundle_build`がQA対象build numberと一致するpositive integerである
- [ ] `notarization_status=Accepted`
- [ ] `codesign=verified`
- [ ] `stapler=validated`
- [ ] `gatekeeper=accepted`
- [ ] unsigned candidateの場合、production releaseとして公開しないことを確認した

## 1. Clean install / first launch

- [ ] 新規ユーザー相当の状態で起動できる
- [ ] 起動直後に不要なAccessibility権限を要求しない
- [ ] Network client entitlementを要求しない
- [ ] Menu Bar itemが表示される
- [ ] Settingsを開ける
- [ ] Quitが正常に終了する
- [ ] 再起動後もクラッシュループしない

## 2. Create Glass

- [ ] user-selected folderからGlassを作成できる
- [ ] folder accessを拒否した場合、設定が半端に保存されない
- [ ] 同じfolderを扱う場合も既存Glassを破壊しない
- [ ] Glass title / placementが正しく表示される
- [ ] folderのdirect childrenだけが表示される
- [ ] hidden itemが意図どおり非表示になる
- [ ] 500-item上限を超えるfolderでもUIが破綻しない

## 3. Filesystem source-of-truth

- [ ] Finderからfileを追加するとGlassへ反映される
- [ ] Finderからfileを削除するとGlassへ反映される
- [ ] Finderからfile名を変更するとGlassへ反映される
- [ ] 外部変更後もアプリ独自キャッシュが古い状態をsource of truthとして残さない
- [ ] connected folderが一時的に利用不能でも他Glassを巻き込まない

## 4. Open / Reveal

- [ ] regular fileをOpenできる
- [ ] Reveal in Finderが正しいfileを選択する
- [ ] fileが操作直前に消えた場合、別fileを誤って開かない
- [ ] directory / package / symlink等がv0.1 contract外なら安全に拒否される

## 5. Copy-only Drop

専用のsource / destination / unrelated folderを作成する。

- [ ] regular fileをGlassへdropするとcopyされる
- [ ] source fileが元の場所に残る
- [ ] source fileの内容・mtime等に意図しない変更がない
- [ ] destinationに同名fileがある場合overwriteしない
- [ ] same-directory dropを安全に拒否する
- [ ] folder dropを安全に拒否する
- [ ] package / symlinkをv0.1 contractどおり拒否する
- [ ] destination pathnameがdirectoryへのsymbolic linkの場合、copy可能としてadvertiseせず安全に拒否する
- [ ] symbolic link先のphysical directoryを直接選択した場合だけ通常のdestination safety判定へ進む
- [ ] 複数fileの一部が失敗した場合、成功/失敗が区別される
- [ ] unrelated folderへfileを生成・削除しない

## 6. Copy interruption / Pending Copy Recovery

可能な範囲でcopy途中の失敗状態をtest fixtureまたは開発用再現手段で作る。

- [ ] Pending Copy Recovery Centerにrecordが表示される
- [ ] staleな画面状態のままmutationを実行できない
- [ ] ownership proof不成立のstagingを削除しない
- [ ] `Remove Incomplete Copy…` はapp-owned stagingだけを対象にする
- [ ] final user-visible fileをRecoveryから削除しない
- [ ] `Discard Metadata…` がuser fileを変更しない
- [ ] Copy中にRecovery mutationを開始できない
- [ ] Recovery mutation中に新しいCopyを開始できない

## 7. Destination Reconnect

- [ ] destination unavailable状態を表示できる
- [ ] 正しい元destinationを選択するとreconnectできる
- [ ] saved / selected双方の`PersistentFolderIdentity.volumeUUIDString`が一致する
- [ ] saved / selected双方の`PersistentFolderIdentity.documentIdentifier`が一致する
- [ ] volume UUIDまたはdocument identifierが異なるfolderは拒否する
- [ ] saved側で記録済みのpersistent identity dimensionがselected側で取得不能ならfail-closedする
- [ ] boot/session-local `ResourceFingerprint`一致だけではreconnect authorityにならない
- [ ] pickerを開いている間にconfig/recordが変わった場合staleとして拒否する
- [ ] reconnectによってGlass ID/title/placementが不必要に変化しない
- [ ] reconnect操作そのものはuser file contentを変更しない

### 7.1 General Glass Source Reconnect (v0.2)

- [ ] bookmark/permission failureなどで`unavailable`になったGlassにReconnect controlが表示される
- [ ] healthyな`ready` / `empty` GlassにはReconnect controlが表示されない
- [ ] pickerをCancelした場合、configuration / runtime / user fileを変更しない
- [ ] 元の同一folderを選択するとGlass ID/title/placement/show-on-all-spacesを維持したまま復旧する
- [ ] volume UUIDまたはdocument identifierが異なる別folderは、pathやfolder名が同じでも拒否する
- [ ] persistent identityを証明できない場合はpath一致へfallbackせずfail-closedする
- [ ] bookmark refresh後にもpersistent identityを再検証する
- [ ] event subscription / initial snapshot / conditional config saveのいずれかが失敗した場合、準備済みaccessとsubscriptionをcleanupする
- [ ] picker表示中またはruntime準備中にconfigurationが変わった場合staleとして拒否し、上書きしない
- [ ] reconnect成功後に外部file変更が再びGlassへ反映される
- [ ] reconnect成功後にアプリを再起動しても同じfolderへ復元できる
- [ ] reconnect操作そのものはuser-owned fileを作成・移動・rename・deleteしない

### 7.2 Connected Folder Actions (v0.2)

- [ ] active runtimeを持つGlassに`Show connected folder in Finder` controlが表示される
- [ ] controlからGlass root folderをFinderで表示できる
- [ ] item選択ではなくconnected root folder自体を表示する
- [ ] Finder表示はread-onlyで、user-owned fileを作成・移動・rename・deleteしない
- [ ] unavailableなどactive runtimeを持たないGlassではstale folder URLを操作authorityとして残さない
- [ ] runtime session終了後はsession-local connected folder URLを破棄する
- [ ] reconnect成功後はReconnect controlからconnected-folder controlへ状態が更新される
- [ ] Glass削除 / app shutdown / configuration recovery restore後に古いconnected folder URLを再利用しない

### 7.3 Glass Display Name Rename (v0.2)

- [ ] Rename controlからGlass表示名を変更できる
- [ ] rename前後でconnected source folderの実ファイル名 / directory名が変化しない
- [ ] bookmark / persistent identity / placement / show-on-all-spaces / createdAtがrenameで変化しない
- [ ] 前後のwhitespace / newlineはtrimされて保存される
- [ ] 空白だけのtitleは拒否される
- [ ] 101文字以上のtitleは拒否される
- [ ] 同じnormalized titleへのrenameでは不要なconfiguration writeを増やさない
- [ ] rename中にconfigurationが変化した場合stale writeとして拒否し、他変更を上書きしない
- [ ] rename成功後にpanel/header表示が更新される
- [ ] rename成功後にアプリを再起動しても新しいGlass表示名が維持される
- [ ] rename中もuser-owned fileを作成・移動・rename・deleteしない

### 7.4 Per-Glass Spaces Behavior (v0.2)

- [ ] `Show Glass on all Spaces` controlでGlass単位に切り替えられる
- [ ] 有効化すると別Spaceへ移動しても同じGlassが表示される
- [ ] 無効化すると通常のSpace所属Window behaviorへ戻る
- [ ] toggle成功後にcontrolの状態表示が更新される
- [ ] toggle状態がアプリ再起動後も維持される
- [ ] title / source / bookmark / persistent identity / placement / createdAtはtoggleで変化しない
- [ ] 同じ状態への更新では不要なconfiguration writeを増やさない
- [ ] toggle中にconfigurationが変化した場合stale writeとして拒否し、他変更を上書きしない
- [ ] copy/drop処理中はSpaces behavior変更を開始しない
- [ ] toggle操作でuser-owned fileを作成・移動・rename・deleteしない

## 8. Recovery manual inspection

- [ ] `Show Incomplete Copy` がfresh assessment後だけ実行される
- [ ] `Show Final File` がfresh assessment後だけ実行される
- [ ] Finder inspectionはread-onlyである
- [ ] 対象fileが直前に置換/削除された場合、古いpathをmutation authorityとして使わない

## 9. Configuration persistence / backup recovery

- [ ] Glass追加後にアプリ再起動して復元される
- [ ] placement変更後に再起動して復元される
- [ ] Glass削除後に再起動して復活しない
- [ ] valid configuration backupをSettingsから復元できる
- [ ] restore中にpanel stateの古いdebounceが復元configを再上書きしない
- [ ] corrupt current configのRecoveryでユーザー選択なしに破壊的rollbackしない
- [ ] current configを読めない起動では`Configuration recovery required`を表示し、Workspace / Menu Bar / `⌘N`から新しいGlassを追加できない
- [ ] configuration recovery required中もSettingsのConfiguration Backup一覧・restore操作は利用できる
- [ ] configuration recovery required中はGlass削除・placement保存・Reset Glass Positions・新しいDrop Copyへ進まない
- [ ] configuration recovery required中も既存fileのOpen / Revealのread-only操作は利用できる
- [ ] valid backupのrestoreと再loadが成功するとrecovery-required lockが解除され、通常のconfiguration mutationを再開できる
- [ ] backup自体はcommitされたが再loadに失敗した場合、再起動または次のRecovery成功までmutationを再開しない
- [ ] restore失敗時に「失敗」と表示しながら実際には別状態へcommit済み、という不整合がない

## 10. Windowing / multi-display

- [ ] Glassの非インタラクティブなbackground / header areaをドラッグしてpanelを移動できる
- [ ] Glass options menuの操作がwindow dragに奪われない
- [ ] file gridのdouble-click / context menu / scrollがwindow dragに奪われない
- [ ] Glass panelをresizeできる
- [ ] position lock buttonでGlassの移動をLock / Unlockできる
- [ ] Lock中はbackground dragで移動せず、file操作・menu操作・resizeは引き続き利用できる
- [ ] position lock状態がアプリ再起動後も維持される
- [ ] Unlock後は再びbackground dragで移動できる
- [ ] Keep on Topを有効にすると他の通常Windowより前面にGlassが維持される
- [ ] Keep on Topを無効にすると通常Window levelへ戻る
- [ ] Keep on Top状態がアプリ再起動後も維持される
- [ ] Keep on TopとPosition Lockを独立して切り替えられる
- [ ] Glassを画面端へdragしても最低80x40ptの操作可能領域がvisible frame内へ残る
- [ ] second displayへ十分表示されているGlassをprimary displayへ勝手に引き戻さない
- [ ] drag reachability補正後のplacementが保存され、再起動後も同じreachable位置へ復元される
- [ ] Reset Glass PositionsはLock中のGlassも明示操作として救出し、Lock状態自体は維持する
- [ ] placementが保存される
- [ ] second displayへ配置できる
- [ ] display切断後もGlassが完全に画面外へ取り残されない
- [ ] `Reset Glass Positions` で全Glassが可視領域へ戻る
- [ ] workspace/config mismatch時にpartial resetを行わない
- [ ] Show on all spacesの挙動が想定どおり

## 11. Menu Bar / Global Shortcut

- [ ] Menu BarからAdd / Show All / Hide All / Settings / Quitを実行できる
- [ ] shortcut未設定時に既存global shortcutを占有しない
- [ ] user-customizable shortcutを設定できる
- [ ] shortcutでHide Allできる
- [ ] 全非表示状態からshortcutでShow Allできる
- [ ] 一部表示中ならHide All側へ遷移する
- [ ] Glass 0件ではno-op
- [ ] Recovery/config mutation中にshortcutでpanelを再生成しない
- [ ] Hide All後のfilesystem refreshで勝手に再表示しない

## 12. Failure isolation

- [ ] 1 Glassのfolder access failureが他Glassを落とさない
- [ ] 1 Glassのsnapshot failureがアプリ全体を終了させない
- [ ] source/destination消失時にsilent overwrite/deleteへ進まない
- [ ] error messageにraw bookmark dataや不要な内部path情報を露出しない

## 13. Supported macOS baseline

少なくとも以下を実機またはRelease相当環境で確認する。

- [ ] macOS 15 baselineで起動・基本操作
- [ ] 現行開発macOSで起動・基本操作
- [ ] macOS 15 baselineでDock / Finder / Applicationsのapp iconがSchneeGlass artworkとして表示され、generic fallback iconにならない
- [ ] 現行開発macOSでapp iconに二重角丸、意図しない透明縁、欠けがない
- [ ] Intelを正式サポートする場合はIntel実機または明示した相当検証を追加する

## 14. Signed production candidate — Developer ID path

Developer ID signing / notarization pipelineは実装済み。このSectionは**実credentialで生成した、そのexact candidate**に対して必須。

- [ ] `.github/workflows/production-release.yml`の`Production Release Candidate` workflowが`main`の対象commitからsuccessしている
- [ ] `codesign --verify --deep --strict` PASS
- [ ] Developer ID Application identityで署名されている
- [ ] TeamIdentifierが想定Team IDと一致する
- [ ] secure signing timestampが存在する
- [ ] Hardened Runtimeが維持されている
- [ ] App Sandbox entitlementが維持されている
- [ ] user-selected read-write entitlementが維持されている
- [ ] 不要なnetwork entitlementが追加されていない
- [ ] `get-task-allow=true`ではない
- [ ] Apple notarization result = `Accepted`
- [ ] notarization ticketをstaple済み
- [ ] `xcrun stapler validate` PASS
- [ ] Gatekeeper assessment PASS
- [ ] quarantine付きダウンロード相当の状態から起動できる
- [ ] signed/stapled artifactに対する最終SHA-256 manifestを生成した
- [ ] final signed ZIPから記録されたbundle identifier / version / build evidenceがQA対象と一致する
- [ ] strict schema v1 evidence validationがPASSする
- [ ] Actions artifactにcredential materialが含まれていない

## 15. Immutable production publication

Manual QAが完了するまで`Publish Production Release`を実行しない。

- [ ] Repository Settingsでrelease immutabilityを有効化済み
- [ ] `main` branch / ruleset / required CIなどRelease governanceを確認済み
- [ ] publication inputのversionがcandidateと一致する
- [ ] publication inputのcandidate run IDがQA対象runと一致する
- [ ] `confirm_manual_qa = true`はこのexact candidateのQA完了後にだけ指定する
- [ ] `confirm_immutable_releases = true`はRepository設定確認後にだけ指定する
- [ ] `confirm_release_governance = true`はbranch / required CI / release-source governance確認後にだけ指定する
- [ ] `confirm_publish = true`は公開意思を最終確認した後にだけ指定する
- [ ] publication workflowがcandidate workflow nameを`Production Release Candidate`として再検証する
- [ ] publication workflowがcandidate workflow pathを`.github/workflows/production-release.yml`として再検証する
- [ ] candidate event=`workflow_dispatch` / branch=`main` / completed-successを再検証する
- [ ] candidate `run_attempt=1`をartifact download前後の単一workflow-run snapshotで再検証し、途中rerunを拒否する
- [ ] candidate commitがDraft作成前にfresh fetchしたcurrent `main`とexact matchする
- [ ] Draft asset validation後、公開コマンド直前に`origin/main`を再fetchし、candidate commitがcurrent `main`とexact matchする
- [ ] schema v1 evidence再検証がPASSする
- [ ] evidence commit SHAがcandidate workflow head SHAと一致する
- [ ] evidence bundle identifier / version / buildの再検証がPASSする
- [ ] `SHA256SUMS` self-check PASS
- [ ] public Release build history取得がPASSする
- [ ] first public Releaseならhistory 0件としてPASSする
- [ ] 既存public Releaseがある場合、candidate `bundle_build > max(public bundle_build)`である
- [ ] historical evidence欠落・malformed時にfail-closedする
- [ ] 同一tag / Releaseが事前に存在しない
- [ ] asset無しDraftの作成時、run-owned Release `databaseId`を同じCreate Release API responseからcaptureしており、後続tag lookupをownership sourceにしていない
- [ ] asset無しDraftの作成後、Draft targetがQA済みcandidate SHAと一致する
- [ ] ZIP / `SHA256SUMS` / `RELEASE_EVIDENCE.txt`はcapture済みrun-owned Release IDへ直接uploadされ、tag lookupをupload targetに使っていない
- [ ] ZIP / `SHA256SUMS` / `RELEASE_EVIDENCE.txt`のDraft upload/asset validation PASS
- [ ] 3ファイルのlocal SHA-256を記録し、公開直前のrun-owned Release snapshotで各`assets[].digest`がexact `sha256:<local hex>`として一致する
- [ ] digest欠落・malformed・同名別内容のassetはpublication前にfail-closedする
- [ ] 公開前に失敗した場合、run-created Draft/tagは自動削除されず、tagとcaptured Release IDを含むmanual-reconciliation guidanceが出る
- [ ] 公開後`isImmutable=true`
- [ ] `isImmutable=false`の場合、mutable public Release/tagは自動削除されず、tagとcaptured Release IDを含むmanual-reconciliation guidanceが出る
- [ ] Release assetsに`SchneeGlass-X.Y.Z.zip`が存在する
- [ ] Release assetsに`SHA256SUMS`が存在する
- [ ] Release assetsに`RELEASE_EVIDENCE.txt`が存在する
- [ ] Release tagがQA済みcandidate source commitを指す
- [ ] 公開直前のrun-owned Release検証がcapture済みRelease IDへの単一snapshot取得で、ID / Draft / prerelease / target / assetsを同じresponseから検証している
- [ ] Draft -> public mutationがtag lookupではなくcapture済みrun-owned Release IDを直接指定している
- [ ] 公開直後のrun-owned Release検証がcapture済みRelease IDへの単一snapshot取得で、ID / Draft / immutable / target / assetsを同じresponseから検証している
- [ ] 公開直後の同じrun-owned Release snapshotで3 assetの`assets[].digest`が公開前と同じlocal SHA-256 mappingに一致する
- [ ] 公開後のRelease `databaseId`がDraft作成直後にcaptureしたrun-owned Release IDと一致する

## 16. Performance / release-window diagnostics

Release windowで500-item Folder Snapshot baselineの最新結果を確認する。

- [ ] `.github/workflows/snapshot-performance.yml`の直近relevant runがPASSしている
- [ ] `SCHNEEGLASS_PERF_RESULT snapshot_500` markerが存在する
- [ ] measurementはmonotonic clockを使用している
- [ ] worst latencyが`0.5s`未満である
- [ ] 単発CI jitterではなく継続的悪化がある場合はDEBT-001のRevisit Triggerとして扱った

PR #39導入時の基準値:

```text
average = 0.055926s
worst   = 0.059213s
limit   = 0.500000s
```

## 17. Final release record

Release時に以下をPR / Release notes / QA recordのいずれかへ残す。

- [ ] commit SHA
- [ ] version / build number
- [ ] tested macOS versions
- [ ] artifact SHA-256
- [ ] canonical CI run
- [ ] compatibility CI run
- [ ] AddressSanitizer status
- [ ] ThreadSanitizer / CodeQL / Snapshot Performance status or release-window evaluation
- [ ] Production Release Candidate workflow run
- [ ] Publish Production Release workflow run
- [ ] manual QA実施者と実施日
- [ ] immutable Release URL / tag
- [ ] known limitations

## Release blockerの扱い

次は即Release blockerとする。

- source file loss / overwrite / move / rename / delete
- ownership proofなしのstaging deletion
- final user-visible fileのRecovery deletion
- stale stateをauthorityにしたmutation
- Sandbox / signing / notarization gate failure
- config restore結果とUI結果の不一致
- supported baselineでのlaunch failure
- candidate workflow identity / source / bundle evidence / checksum不一致
- release evidence schema violation
- public build number再利用 / 巻き戻し
- public build historyを証明できない状態
- release governance未確認でのpublication
- mutable public Release

軽微な表示差分は個別判断できるが、File Safety / Recovery / Release integrity failureより優先してはならない。
