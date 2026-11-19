import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedPanelControlsHaveBothLanguagesAndFallback() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  for key in SchneeGlassPanelText.allCases {
    #expect(!key.resolve(locale: en).isEmpty)
    #expect(key.resolve(locale: ja) != key.resolve(locale: en))
    #expect(key.resolve(locale: fallback) == key.resolve(locale: en))
  }
  #expect(SchneeGlassPanelText.lockPosition.resolve(locale: en) == "Lock Glass position")
  #expect(SchneeGlassPanelText.unlockPosition.resolve(locale: ja) == "Glassの位置固定を解除")
}

@Test
func localizedPanelOpacityPreservesPercentageAndRenameSafety() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  for percentage in ["100%", "90%", "80%", "70%"] {
    let english = SchneeGlassPanelText.opacity(percentage: percentage, locale: en)
    let japanese = SchneeGlassPanelText.opacity(percentage: percentage, locale: ja)
    #expect(english == "Opacity " + percentage)
    #expect(japanese == "不透明度 " + percentage)
  }
  let detail = SchneeGlassPanelText.renameDetail.resolve(locale: ja)
  #expect(detail.contains("表示名だけ"))
  #expect(detail.contains("接続先フォルダの名前は変更されません"))
  #expect(SchneeGlassPanelText.glassName.resolve(locale: ja) == "Glass名")
}
