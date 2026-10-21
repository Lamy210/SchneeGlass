# ADR-0011: Developer IDを利用しない配布方針

- Status: Accepted
- Date: 2026-10-21
- Scope: v0.2以降の継続開発と配布判断
- Supersedes: ADR-0006の今後の配布方針（過去の実装・検証履歴は変更しない）

## Context

SchneeGlassの利用・開発を続けるにあたり、プロジェクトは**Apple Developer ID署名を実施しない**ことを選択した。

現在の公開済み実例は`v0.1.1`の**ad-hoc署名済み、Apple未公証**のGitHub Releaseである。v0.2.0/build 3は機能実装とCI検証が進んでいるが、まだ公開済みReleaseではない。

リポジトリには過去の計画に基づくDeveloper ID署名、Notarization、署名済みProduction Releaseのコードと検証が存在する。これらは導入済みであることと、今後実行することを区別する。

## Decision

1. **Developer ID証明書の取得・設定・利用、App Store Connect notarization credentialの登録、`notarytool`によるApple公証、`production-release`環境を使った署名済み候補の発行を今後の開発・リリースの必須条件にしない。**
2. 配布はGitHub Releasesを中心に、**ad-hoc署名を用いる非公証配布**を候補とする。公開前に手動QA、配布物の由来、`codesign --verify`、Sandbox/Hardened Runtime、SHA-256チェックを確認する。
3. 現行`Ad-Hoc Release Candidate`は`workflow_dispatch`からダウンロードできる**14日保存の検証用Actions artifact**であり、**GitHub Releaseを自動公開しない**。その成果物をそのまま信頼済み本番製品と表示しない。
4. 将来の公開用ad-hoc経路は、別PRでReleaseのタグ・version・build・source SHA・payload checksum・手動QA・配布済み履歴・再実行時の挙動を設計・テストする。公開済みReleaseを黙って差し替えず、新version/buildとして発行する。
5. Developer ID用の既存workflow/検証・`RELEASE_EVIDENCE.txt`契約は履歴と安全性のため残すが、**現行の配布入口として案内・起動しない**。将来復活させる場合には新しい明示的な判断とレビューを要する。
6. ブランチ保護・required CI・Release immutability等の**一般的なリポジトリ統制は引き続き必要**である。Developer ID credentialが不要だからといって統制を弱めない。
7. 新機能開発をApple credential待ちで停止しない。ただしFile Safety、データ保全、1 PR = 1 conceptual change、意味のあるテスト、CI成功後のマージ条件は従来どおり維持する。

## 信頼性・インストール上の制約

- **ad-hoc署名はDeveloper ID署名ではなく、Appleの公証済み証明でもない。** macOS Gatekeeperにより初回起動が拒否される場合がある。
- README、Releaseノート、配布ファイル名では未公証であることを明示し、ユーザーに安全性・真正性がAppleによって確認されたかのように説明しない。
- ZIPとSHA256SUMSは同一Release由来であることを確認する。checksumは改ざん検知に役立つが、取得元自体の真正性を独立して保証しない。
- Gatekeeperをシステム全体で無効にする、quarantine属性を一括削除するなどの回避をインストール手順として要求しない。ユーザーが配布元を確認し、macOSの個別アプリ許可UIで判断する。
- Sandbox / security-scoped access / non-destructive file operation contractはそのまま維持する。Apple署名の有無とファイル操作権限は別の問題として扱う。

## Consequences

- Apple Developer ProgramやNotarizationの資格情報なしで開発・配布検証を進められる。
- Gatekeeper UX、配布物の信頼表示、アップデートや失効時の運用に制約が残る。
- 既存のProduction Release CandidateおよびPublish Production Releaseを**現在の配布手順として使わない**。ad-hocの公開用経路の設計・検証が別途必要。
- Issue #33のDeveloper ID署名・Notarizationを「未完了の必須タスク」として扱わず、repository governanceと今後のad-hoc配布準備を分けて追跡する。

## Alternatives

- Developer ID署名 + Apple notarization: 現プロジェクトの判断により採用しない。
- Mac App Store: 追加の審査・署名手続きが必要になるため今回対象外。
- 完全未署名の配布: 既存のad-hoc署名のintegrity checksより劣るため、通常の配布経路として採用しない。
