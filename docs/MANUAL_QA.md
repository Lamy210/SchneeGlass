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

QAは使い捨てのtest folderで行い、実業務folderや唯一の原本を使用しないこと。

## 0. Candidate identification

- [ ] 対象commit SHAを記録した
- [ ] `MARKETING_VERSION`を記録した
- [ ] `CURRENT_PROJECT_VERSION`を記録した
- [ ] 対象artifact名を記録した
- [ ] `SHA256SUMS`が存在する
- [ ] `shasum -a 256 -c SHA256SUMS` がPASSする
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
- [ ] fingerprintが一致しないfolderは拒否する
- [ ] pickerを開いている間にconfig/recordが変わった場合staleとして拒否する
- [ ] reconnectによってGlass ID/title/placementが不必要に変化しない
- [ ] reconnect操作そのものはuser file contentを変更しない

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
- [ ] restore失敗時に「失敗」と表示しながら実際には別状態へcommit済み、という不整合がない

## 10. Windowing / multi-display

- [ ] Glass panelを移動・resizeできる
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
- [ ] Intelを正式サポートする場合はIntel実機または明示した相当検証を追加する

## 14. Signed production candidate — Developer ID path

このSectionはDeveloper ID signing pipeline実装後に必須。

- [ ] `codesign --verify --deep --strict` PASS
- [ ] Developer ID Application identityで署名されている
- [ ] Hardened Runtimeが維持されている
- [ ] App Sandbox entitlementが維持されている
- [ ] user-selected read-write entitlementが維持されている
- [ ] 不要なnetwork entitlementが追加されていない
- [ ] Apple notarization result = Accepted
- [ ] notarization ticketをstaple済み
- [ ] `xcrun stapler validate` PASS
- [ ] Gatekeeper assessment PASS
- [ ] quarantine付きダウンロード相当の状態から起動できる
- [ ] signed/stapled artifactに対する最終SHA-256 manifestを生成した

## 15. Final release record

Release前に以下をPR / Release notes / QA recordのいずれかへ残す。

- [ ] commit SHA
- [ ] version / build number
- [ ] tested macOS versions
- [ ] artifact SHA-256
- [ ] canonical CI run
- [ ] compatibility CI run
- [ ] sanitizer status
- [ ] Release Candidate / production release workflow run
- [ ] manual QA実施者と実施日
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

軽微な表示差分は個別判断できるが、File Safety / Recovery / Release integrity failureより優先してはならない。
