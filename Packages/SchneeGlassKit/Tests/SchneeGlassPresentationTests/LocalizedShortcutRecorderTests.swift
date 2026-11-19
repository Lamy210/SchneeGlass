import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedShortcutRecorderLabelDescribesGlobalToggleAndFallsBackToEnglish() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  let key = SchneeGlassSettingsText.shortcutRecorder
  #expect(key.resolve(locale: en) == "Show or hide all Glasses global shortcut")
  #expect(key.resolve(locale: ja).contains("すべてのGlassを表示・非表示"))
  #expect(key.resolve(locale: ja).contains("グローバルショートカット"))
  #expect(key.resolve(locale: fallback) == key.resolve(locale: en))
}
