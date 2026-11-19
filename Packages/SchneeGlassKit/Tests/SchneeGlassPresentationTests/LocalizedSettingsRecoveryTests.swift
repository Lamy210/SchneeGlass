import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedSettingsTextHasBothLanguagesAndEnglishFallback() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let unsupported = Locale(identifier: "fr_FR")
  for key in SchneeGlassSettingsText.allCases {
    #expect(!key.resolve(locale: en).isEmpty)
    #expect(key.resolve(locale: ja) != key.resolve(locale: en))
    #expect(key.resolve(locale: unsupported) == key.resolve(locale: en))
  }
}

@Test
func localizedSettingsRestoreConfirmationPreservesSafetyAndDate() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let date = "2026-11-19 09:00"
  let english = SchneeGlassSettingsText.restoreConfirmation(date: date, locale: en)
  let japanese = SchneeGlassSettingsText.restoreConfirmation(date: date, locale: ja)
  #expect(english.contains(date))
  #expect(japanese.contains(date))
  #expect(english.contains("preserve the current configuration before replacing it"))
  #expect(english.contains("will not be moved, renamed, deleted, or replaced"))
  #expect(japanese.contains("置き換える前に現在の設定を保存"))
  #expect(japanese.contains("移動・改名・削除・置換されません"))
}

@Test
func localizedSettingsRecoveryMessagesDistinguishFailureFromRestoredState() {
  let ja = Locale(identifier: "ja_JP")
  #expect(SchneeGlassSettingsText.backupReadFailed != .restoreFailed)
  #expect(SchneeGlassSettingsText.configurationRestored != .restoredNeedsRestart)
  #expect(SchneeGlassSettingsText.restoreFailed.resolve(locale: ja).contains("変更されていません"))
  #expect(SchneeGlassSettingsText.restoredNeedsRestart.resolve(locale: ja).contains("再起動"))
  #expect(SchneeGlassSettingsText.waitForCopy.resolve(locale: ja).contains("コピーが完了"))
}
