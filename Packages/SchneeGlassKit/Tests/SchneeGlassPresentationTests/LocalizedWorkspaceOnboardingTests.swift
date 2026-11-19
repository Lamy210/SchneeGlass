import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedWorkspaceOnboardingPreservesOriginalOwnershipContract() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let english = GlassLocalizedText.firstGlassDetail.resolve(locale: en)
  let japanese = GlassLocalizedText.firstGlassDetail.resolve(locale: ja)
  #expect(english.contains("stores a reference to the folder"))
  #expect(english.contains("does not take ownership of your files"))
  #expect(japanese.contains("フォルダへの参照を保存するだけ"))
  #expect(japanese.contains("ファイルの所有権は取得しません"))
  #expect(GlassLocalizedText.addGlass.resolve(locale: en) == "Add Glass")
  #expect(GlassLocalizedText.addGlass.resolve(locale: ja) == "Glassを追加")
}

@Test
func localizedWorkspaceRecoveryPreservesRequiredRestoreOrder() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let english = GlassLocalizedText.configurationRecoveryDetail.resolve(locale: en)
  let japanese = GlassLocalizedText.configurationRecoveryDetail.resolve(locale: ja)
  #expect(english.contains("restore a valid Configuration Backup"))
  #expect(english.contains("before adding or changing a Glass"))
  #expect(japanese.contains("Glassを追加・変更する前に"))
  #expect(japanese.contains("有効な設定バックアップを復元"))
  #expect(GlassLocalizedText.restoringStatus.resolve(locale: ja) == "復元中…")
  #expect(GlassLocalizedText.restoringGlasses.resolve(locale: ja) == "Glassを復元中…")
}
