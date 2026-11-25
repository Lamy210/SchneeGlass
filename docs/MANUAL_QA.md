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

## Ad-Hoc candidate QA (active path; no Developer ID)

This section applies to the currently supported **ad-hoc-signed, not Apple-notarized** candidate workflow. It does **not** certify an ad-hoc artifact as an Apple-trusted production Release. The Developer ID production checklist below is retained for historical reference and is **not a release prerequisite** under [ADR-0011](adr/0011-adhoc-distribution-without-developer-id.md).

- [ ] Candidate was generated via `Ad-Hoc Release Candidate` **workflow_dispatch** on exact current `main`; record run ID and `GITHUB_SHA`.
- [ ] Candidate version/build and ZIP filename match the exact project source; record `BUILD_INFO.txt` including `source_commit`.
- [ ] `BUILD_INFO.txt` declares `code_signature=adhoc`, `apple_developer_id_signed=false`, `apple_notarized=false`.
- [ ] `SHA256SUMS` verifies the candidate ZIP, and files are from the same Actions artifact/source.
- [ ] `codesign --verify --deep --strict` succeeds on the extracted app.
- [ ] Hardened Runtime, App Sandbox, user-selected read/write entitlement and absence of unexpected network entitlement are confirmed.
- [ ] Gatekeeper first-launch behavior is checked on supported macOS, including any app-specific user approval; never disable Gatekeeper globally or strip quarantine as a workaround.
- [ ] Menu Bar, folder selection, direct-child listing, Glass positioning, restart recovery, Open / Reveal, copy-only Drop, cancellation and Pending Copy Recovery are exercised with disposable sample files.
- [ ] No user-owned source files are moved, renamed, deleted, overwritten or silently discarded.
- [ ] Any candidate requiring correction is rebuilt from a fresh exact `main` source. A passing candidate **must not** be automatically published as a GitHub Release.
- [ ] Future public ad-hoc release follows a separately reviewed publication process under [Issue #520](https://github.com/Lamy210/SchneeGlass/issues/520).

## 0. Candidate identification (historical Developer ID production path)

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
- [ ] WorkspaceおよびDesktop Glassが`.loading`の間、VoiceOverで「フォルダを読み込み中… / Loading folder…」の本文案内が1回読めることを確認する。ヘッダーの装飾的なスピナーを個別の同名読み上げ項目として列挙しない。読込完了時はReady/Emptyの状態へ移行し、説明テキストが消えることを日英・macOS 15/26で確認する（実機未確認）。
- [ ] folderのdirect childrenだけが表示される
- [ ] hidden itemが意図どおり非表示になる
- [ ] 500-item上限を超えるfolderでもUIが破綻しない
- [ ] Glass optionsの「Refresh Files」で接続中のフォルダを手動更新できる。通常時・空フォルダ・enumeration failureの復旧を確認する
- [ ] 手動更新の連打で読み取りが並列化されない。更新中のFSEventsは後続snapshotとして扱い、終了・Glass削除中に古いsnapshotやアクセス権が残らない
- [ ] コピー中・接続不能・停止後はRefreshが無効。フォルダidentity差し替えは従来通り不可用となり再接続が必要
- [ ] Glass optionsの「Filter Files…」で検索欄を開閉できる
- [ ] File TypeをAll Types / Files / Folders / Packages / Links and Aliases / Otherに切り替えられる。名前とのAND条件、ソート順、対象ID、取得済み範囲の件数表示を維持する
- [ ] Filterを閉じると名前・種類が両方リセットされ、再表示時にAll Typesとなる。種類は他Glassや再起動へ永続化しない
- [ ] VoiceOverでFile Typeと選択中の項目を確認でき、小さいGlassでも既存スクロール・Open/Reveal・Dropの操作を妨げない
- [ ] Ready状態のGlass optionsからFilter Filesを開くと名前入力欄へfocusが移る。通常の入力・日本語IME変換を検証し、IME候補のEscapeは変換を取り消して検索を閉じないことを確認する。入力欄がexit commandを受けた場合はEscapeで閉じ、名前・種類の両条件を解除する
- [ ] Filterのclose button / Hide File Filter / Escapeで同じreset動作。空・不可用・読込失敗状態で新規に開けない。すでに開いていた場合は閉じられる。snapshotが一時的に空/失敗になり復旧しても条件は保持し、入力欄へfocusを奪い返さない
- [ ] 他のGlass、検索以外の操作、Remove確認ダイアログ、copy cancellation、Picker、IME候補がEscapeを使う場合の競合がないことをmacOS 15/26で確認する
- [ ] 大文字小文字・アクセントの違いを無視してファイル名を絞り込める
- [ ] 絞り込みは表示済み500件以内に限定され、source folderの再走査やmutationを行わない
- [ ] Sort Displayed Files / Folders Firstの順序を絞り込み中も維持する
- [ ] 検索時は取得済みsnapshot内の一致数 / 取得数をグリッド上部に表示する。0件でもfolder全体に存在しないとは表示しない
- [ ] truncate時は検索対象外の項目があることを表示する（500件と501件を別々に確認）
- [ ] 空白queryは検索として扱わない。閉じると取得済み全項目に戻り、truncateの案内は残る
- [ ] 小さいGlass / Compact Tiles / VoiceOverでも件数と検索範囲が読める。既存のconnected-folder Finder操作で全体を確認できる
- [ ] ファイル名フィルターでOpen / Reveal / Copy Dropの操作権限やtargetが変化しない
- [ ] Glassごとの検索状態は独立し、アプリ再起動後に永続化されない

## 3. Filesystem source-of-truth

- [ ] Finderからfileを追加するとGlassへ反映される
- [ ] Finderからfileを削除するとGlassへ反映される
- [ ] Finderからfile名を変更するとGlassへ反映される
- [ ] 外部変更後もアプリ独自キャッシュが古い状態をsource of truthとして残さない
- [ ] connected folderが一時的に利用不能でも他Glassを巻き込まない

## 4. Open / Reveal

- [ ] regular fileをOpenできる
- [ ] Reveal in Finderが正しいfileを選択する
- [ ] Desktop GlassとWorkspaceの両方でmacOSのキーボードナビゲーションを有効にし、Tab / Shift+Tabでfile tileへ移動でき、focusが見える。Return / Spaceは対象のfileを開き、長押しで重複起動しない。修飾キー付きshortcutと検索TextFieldの入力は奪わない
- [ ] VoiceOverでfile名・種類・button traitを確認し、標準activateでOpen、ActionsからReveal in Finderが正しいitemを選ぶ。通常のsingle-clickではOpenしない。double-clickとcontext menuを維持する
- [ ] filter・sort・snapshot更新でfocus対象が消えたとき、削除済み・別名・別Glassのitemを誤って開かない。小さいGlass、複数Glass、VoiceOverとキーボードナビゲーションの同時使用、copy overlay中も確認する
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
- [ ] ドラッグ中のファイルURL一覧と、Drop確定時にPasteboardから再取得したURL一覧が不一致ならCopyを受理しない。複数ファイルの順序入れ替えは同一内容として扱い、追加・削除・置換は拒否する。アプリ層のcopy直前再プランも維持する（synthetic単体試験はあり、Pasteboard差し替えの実機操作は未検証）
- [ ] Drag元がCopyを許可しない操作マスク（Moveのみ、Linkのみ、None）を返す場合、GlassはCopyをadvertiseせず、Dropをdispatchしない。Copy許可を含む複数操作マスクではCopyだけを採用する。modifierキーで途中からCopy不可になった場合は既存hover承認を破棄し、Copy許可復帰後も再検証を要する（実機未確認）
- [ ] 同じファイル一覧をGlassにhoverし続け、定期的なcopy可否の再検証が始まった場合は、旧`.copy`判定を新しい承認として再利用せず一時的にcopy不可とする。新しい検証で許可された場合だけcopy可能表示へ復帰し、拒否時はcopy不可を維持する。hover中の権限変更・外部file変更時も、実コピー前のアプリ層再プランを確認する（AppKit実機挙動は未検証）
- [ ] symbolic link先のphysical directoryを直接選択した場合だけ通常のdestination safety判定へ進む
- [ ] 同じGlassでファイルコピー実行中、重複したhover/Dropを拒否しても既存のコピー進捗・Cancel Copy操作が消えず、進行中のコピーが継続する。copy直前の非同期再プラン中も二重Dropは拒否する（この項目は実機未確認）
- [ ] 同じGlassでDrop実行予約中（コピー本体の開始前）に削除メニューを開いても、WorkspaceとDesktopの両方で削除が無効となる。コピー完了後のidle状態では再び操作できる（実機未確認）
- [ ] Glass削除確認をidle中に開き、確認確定前に同じGlassへhoverまたはDrop実行を開始した場合、確定済みダイアログから削除処理が到着しても最新の状態で拒否する。hover/Drop終了後は新しい削除操作ができる（実機未確認）
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
- [ ] 大きい単一fileのCopy中にCancel Copyすると、現在fileの完了待ちではなくcopy途中でcancelされる
- [ ] 単一fileのcopy途中cancel後、final fileは生成されず、partial stagingはPending Copy Recoveryから安全に扱える

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

- [ ] Workspaceで接続不能によるドロップ拒否を確認する。ドロップ終了→unavailableなら元フォルダ再接続、接続が維持されるならRefresh Filesを案内し、Glassの削除・再登録を復旧の前提としない。Desktopの簡略表示は維持する

- [ ] bookmark/permission failureなどで`unavailable`になったGlassにReconnect controlが表示される
- [ ] healthyな`ready` / `empty` GlassにはReconnect controlが表示されない
- [ ] Workspaceのunavailable状態に直接Reconnect Original Folder…を表示する（Glass optionsを開く必要なし）。Tab/VoiceOverから操作できることを確認する。構成変更中・copy/drop中など既存modelの許可条件を満たさない場合は無効化する
- [ ] 同名Glassが複数あっても、選択したGlass IDだけを再接続する。WorkspaceからCancel・別folder拒否・正常再接続を確認し、Desktop Glass側の状態も追従する
- [ ] unavailableの案内は再接続を優先し、Glass削除・再作成やPending Copy Recoveryを通常のsource reconnectとして案内しない
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
- [ ] WorkspaceのGlass optionsからShow Connected Folder in Finderを実行し、選択したGlassの接続先だけをFinderで表示する。同名Glass、再接続後、configuration restore中・終了開始後・接続喪失後のメニュー状態と実行時guardを確認する
- [ ] WorkspaceのGlass optionsからRefresh Filesを実行できる。ready/empty/再試行可能なfailedのみ許可し、loading/unavailable/unexpected failure、copy/drop、設定変更中、同じGlassの手動更新中は無効化する。対象Glass以外を更新しないこと、更新後のsnapshotとファイル操作対象が正しいことを確認する
- [ ] item選択ではなくconnected root folder自体を表示する
- [ ] Finder表示はread-onlyで、user-owned fileを作成・移動・rename・deleteしない
- [ ] unavailableなどactive runtimeを持たないGlassではstale folder URLを操作authorityとして残さない
- [ ] runtime session終了後はsession-local connected folder URLを破棄する
- [ ] reconnect成功後はReconnect controlからconnected-folder controlへ状態が更新される
- [ ] Glass削除 / app shutdown / configuration recovery restore後に古いconnected folder URLを再利用しない

### 7.2.1 Workspace Glass Name Search

- [ ] Workspaceの検索ボタン / Command+Fで検索欄にfocusする。日本語、大小文字、前後空白、同名Glass、0件、全件を確認し、件数と表示順・操作対象IDが正しいことを確認する
- [ ] 検索中でもidle以外のGlassを表示し、drag/drop/copyの進捗・取消操作を失わない。再接続や設定変更の既存guardは維持する
- [ ] Clearで全件に戻り、Done / 検索欄のEscapeで検索状態を解除する。最後のGlassを削除した場合にも検索状態を解除する。VoiceOver/Tabで操作でき、設定・原本・Desktop Glassには影響しない

### 7.2.2 Workspace Glass Status Filter

- [ ] 検索欄の状態選択でAll States / Connected (ready) / Empty / Loading / Unavailable / Failedを切り替え、名称検索とのAND条件を確認する。EmptyをConnectedに混入させず、FailedとUnavailableを区別する
- [ ] 状態変更・再接続後に結果が追従し、idle以外のGlassは条件不一致でも進捗と取消操作を維持する。Clear / Done / Escape / 最後のGlass削除で状態フィルターも解除される
- [ ] 520ptの最小Workspace幅、Tab/VoiceOver、日本語の名称、0件時の案内を確認する。検索欄を閉じた状態の基準画像・設定・原本・Desktop Glassは不変

### 7.3 Glass Display Name Rename (v0.2)

- [ ] Rename controlからGlass表示名を変更できる
- [ ] WorkspaceのGlass optionsからRename Glass…を開くと現在の表示名が入力される。Cancelで変更せず、Renameで対象Glass IDのみ変更する。同名Glass、名称・状態フィルター中、他画面の更新、copy/drop・設定変更中の無効化と実行時guard、Tab/VoiceOverを確認する
- [ ] Workspaceから空白・101文字超の入力、保存競合・保存失敗を操作し既存のuserMessageが表示され、原本・他Glassの状態が変化しないことを確認する
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

### 7.5 Desktop Glass Snap Presets (v0.2)

- [ ] Snap menuからTop Left / Top Right / Bottom Left / Bottom Right / Centerを選べる
- [ ] snap後もGlassの現在sizeを維持する
- [ ] menu bar / Dockを除いたcurrent displayのvisible frame基準で配置される
- [ ] second display上のGlassはそのdisplay内でsnapされ、primary displayへ勝手に戻らない
- [ ] oversized frameはcurrent displayへ収まるように安全にboundedされる
- [ ] Position Lock中でも明示的なSnap操作は実行でき、Lock状態自体は維持される
- [ ] snap後のplacementが保存され、アプリ再起動後も同じ位置へ復元される
- [ ] snap中にconfiguration mutationが進行中なら新しいsnapを開始しない
- [ ] snap操作でuser-owned fileを作成・移動・rename・deleteしない

### 7.6 Compact Window Controls (v0.2)

- [ ] small-width Glassでもtitlebar controlsがcontent/headerを過度に圧迫しない
- [ ] Position Lockは直接buttonから切り替えられる
- [ ] Rename / Finder / Keep on Top / All Spaces / Snapは`Glass window options` menuから実行できる
- [ ] unavailable GlassではReconnectが直接見える状態を維持する
- [ ] Keep on Top / All Spacesの現在状態がmenu内で判別できる
- [ ] unavailable/failed時にstale Finder actionをmenuへ表示しない
- [ ] configuration mutation中はRename / All Spaces / Snapの実行可否が既存policyに従う
- [ ] compact化によってfile grid / context menu / drag / resize操作が阻害されない

### 7.7 Per-Glass Opacity Presets (v0.2)

- [ ] Glass window optionsから100% / 90% / 80% / 70%を選べる
- [ ] 選択したopacityがpanel全体へ即時反映される
- [ ] 100%へ戻すと保存overrideを削除してdefault behaviorへ戻る
- [ ] opacity presetがアプリ再起動後も維持される
- [ ] Glassごとに独立したopacityを設定できる
- [ ] Position Lock / Keep on Top / All Spacesとは独立して変更できる
- [ ] malformed / unsupported persisted opacityは100%へfail-safeする
- [ ] Glass削除時にstale opacity preferenceをcleanupする
- [ ] 70%でもfile grid / context menu / drag / resize / reconnect操作が利用できる
- [ ] opacity操作でGlass configurationやuser-owned fileを変更しない

### 7.8 Compact File Tiles (v0.2)

- [ ] Glass window optionsからCompact File TilesをON/OFFできる
- [ ] compact ONで同じGlass幅により多くのfile tileを表示できる
- [ ] compact OFFで従来のcomfortable layoutへ戻る
- [ ] file icon / title / double-click / context menuの意味と操作は変わらない
- [ ] settingがGlass単位で独立し、アプリ再起動後も維持される
- [ ] Position Lock / Keep on Top / All Spaces / Opacityとは独立して変更できる
- [ ] Glass削除時にstale compact-file preferenceをcleanupする
- [ ] density切替でsource folder / Glass configuration / placementを変更しない
- [ ] density切替でuser-owned fileを作成・移動・rename・deleteしない

### 7.9 Per-Glass File Sorting (v0.2)

- [ ] Glass window optionsのSort Displayed FilesからName / Modified / Sizeを切り替えられる
- [ ] NameはFinder風の自然順で表示され、同名時も表示順が安定する
- [ ] Modifiedは更新日時が新しいitemから並び、日時不明itemは末尾へ送られる
- [ ] Sizeはsizeが大きいitemから並び、size不明itemは末尾へ送られる
- [ ] sortを切り替えてもdouble-click Open / Reveal in Finder / context menuの対象が変わらない
- [ ] Desktop Glass optionsのShow as List / Show as Iconsで縦並びとアイコングリッドを往復できる。初期値はIcons、Workspaceは従来のグリッド。表示modeはGlass ID単位の端末ローカル設定として永続化し、hide/show、panel再生成、再起動、空/失敗からの復旧でも維持する。JSON構成backup/recoveryの対象外であり検索条件は保存しない
- [ ] Listでも名前・種類のAND検索、folders first、sort順、500件の取得範囲と件数表示、0件表示、正しいFileIdentityを維持する。長い日本語/英語filename、狭いpanel、light/dark、VoiceOver、Tab/Return/Space、double-click/Revealを確認する
- [ ] Listの補助行に取得済みの通常file size / content modification dateを表示する。0 byteと未取得のsizeを区別し、directory/package/alias/symlink/unsupportedのsizeは表示しない。metadata欠損時は空の補助行を作らず、Icons/Workspaceは従来の表示を維持する
- [ ] 日本語/英語locale、システムtimezone、狭いGlass、長いfilename、VoiceOverで補助情報と対象fileの関連を確認する。更新後は既存のsnapshot refreshで追従し、容量集計やリンク先の読み取りは行わない
- [ ] Drop/copy中、構成変更中、非authoritative状態では表示mode変更不可。表示変更前後で原本/JSON構成/配置/権限は不変。グリッドのdensityを変更してListを経由しIconsへ戻してもdensity設定を維持する
- [ ] 別Glassの表示modeには影響しない。構成が一時的に読めずpanelが消えても保存状態を削除しない。authoritativeな構成でGlass削除を確認したときのみ不要なIDを除去する。再作成された別IDはIconsから開始する
- [ ] sort状態がGlass単位で独立し、アプリ再起動後も維持される
- [ ] Compact File Tiles / Opacity / Position Lockなど他のWindow UX preferenceと独立する
- [ ] Glass削除時にstale sort preferenceをcleanupする
- [ ] FSEvents refresh後も選択済みsort orderで再表示される
- [ ] 500-item safety limitを超えるfolderでは、sortが取得済みsnapshotだけへ適用されることを誤認させない
- [ ] sort操作でFolderSnapshot本体 / Glass configuration / source folderを変更しない
- [ ] sort操作でuser-owned fileを作成・移動・rename・deleteしない

### 7.10 Folders First (v0.2)

- [ ] Glass window optionsからFolders FirstをON/OFFできる
- [ ] ONではdirectoryだけがfile/package/aliasより前へ表示される
- [ ] package / alias / symbolic linkをdirectory groupへ誤分類しない
- [ ] directory group内・file group内では選択中のName / Modified / Size sortを維持する
- [ ] OFFでは純粋な選択中sort orderへ戻る
- [ ] settingがGlass単位で独立し、アプリ再起動後も維持される
- [ ] File Sort / Compact File Tiles / Opacityなど他Preferenceと独立する
- [ ] Glass削除時にstale Folders First preferenceをcleanupする
- [ ] grouping操作でFolderSnapshot / Glass configuration / source folderを変更しない
- [ ] grouping操作でuser-owned fileを作成・移動・rename・deleteしない

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
- [ ] 初期configuration load完了前にSettingsのConfiguration Backup restoreを実行してもconfiguration replacementへ進まない
- [ ] 初期configuration loadが成功するとSettingsのConfiguration Backup restoreを実行できる
- [ ] 初期configuration loadが失敗してrecovery requiredになった場合はSettingsのConfiguration Backup restoreを利用できる
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
- [ ] Show Glass / Hide Glassでは同名Glassに構成順の番号付きlabelを表示する。実名が番号付きlabelやそのfallbackと一致しても表示名が重複せず、対象Glass IDのみ操作する。Glass名の変更・削除後にメニューを開き直して更新を確認し、長い日本語名とVoiceOverでも識別性を確認する
- [ ] shortcut未設定時に既存global shortcutを占有しない
- [ ] user-customizable shortcutを設定できる
- [ ] shortcutでHide Allできる
- [ ] 全非表示状態からshortcutでShow Allできる
- [ ] 一部表示中ならHide All側へ遷移する
- [ ] Glass 0件ではno-op
- [ ] Recovery/config mutation中にshortcutでpanelを再生成しない
- [ ] Hide All後のfilesystem refreshで勝手に再表示しない

## 11.1 Graceful application termination

- [ ] Command-Qで終了するとworkspace shutdown完了後にprocessが終了する
- [ ] Glassを移動/resizeした直後（通常debounce完了前）にCommand-Qして再起動しても、最後のplacementが復元される
- [ ] Add Glass / Backup Restore / Reset Positionsなどの設定操作中にQuitしても、終了処理がbusy retryで無期限待機しない
- [ ] Rename / Show on All Spaces / Remove Glass / placement save中にQuitしても、対象configuration mutationのcancel/commit cleanup完了前にtermination replyを返さない
- [ ] 既存configuration mutationをquiesceした後のfinal placement flushがbusy stateを引きずらず、最新placementを1回だけ保存できる
- [ ] debounce済みplacement taskがすでに保存処理へ入っている状態でQuitしても、そのtaskをcancel+joinしてからfinal placement flushへ進む
- [ ] Pending Copy RecoveryのRefresh / Inspect in Finder / Reconnect Destination中にQuitしても、security-scoped accessやconfiguration更新のcleanup完了前にtermination replyを返さない
- [ ] Remove Incomplete Copy / Discard Metadata中にQuitしても、Recovery mutation leaseとSchneeGlass-owned metadata/staging cleanupの終了をjoinしてからprocess終了へ進む
- [ ] termination開始後は新しいPending Copy Recovery操作を開始しない
- [ ] Dock > Quitで同じshutdown pathを通る
- [ ] Menu BarのQuit SchneeGlassで同じshutdown pathを通る
- [ ] system termination requestでも同じshutdown pathを通る
- [ ] active Glass sessionのFSEvents subscriptionが終了時にstopされる
- [ ] security-scoped folder accessが終了時にreleaseされる
- [ ] pending authoritative Drop planが終了時にabandonされる
- [ ] active copyがある場合、既存Pending Copy recovery contractに従ってsession stop完了を待ってから終了する
- [ ] shutdown待機中の重複Quit requestでworkspace shutdownを二重開始しない
- [ ] shutdown完了後のtermination replyは1回だけ行われる
- [ ] bootstrap failureでworkspaceが存在しない場合はasync shutdown待機なしで終了できる
- [ ] 起動直後 / Glass restore中にQuitしてもfalse recovery failureを表示せずcleanup完了後に終了する
- [ ] final willTerminate cleanupでDesktop Glass panel / observer / global UI cleanupが従来どおり行われる

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
