import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedMenuLabelsPreserveEnglishAndJapaneseFallback() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  for key in SchneeGlassMenuText.allCases {
    #expect(!key.resolve(locale: en).isEmpty)
    #expect(key.resolve(locale: ja) != key.resolve(locale: en))
    #expect(key.resolve(locale: fallback) == key.resolve(locale: en))
  }
  #expect(SchneeGlassMenuText.showAll.resolve(locale: en) == "Show All Glasses")
  #expect(SchneeGlassMenuText.hideAll.resolve(locale: en) == "Hide All Glasses")
  #expect(SchneeGlassMenuText.addGlassCommand.resolve(locale: ja) == "Glassを追加")
}

@Test
func localizedPositionResetPreservesFileSafetyContract() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let english = SchneeGlassMenuText.resetDetail.resolve(locale: en)
  let japanese = SchneeGlassMenuText.resetDetail.resolve(locale: ja)
  #expect(english.contains("current main display"))
  #expect(english.contains("will not be moved, renamed, or deleted"))
  #expect(japanese.contains("現在のメインディスプレイ"))
  #expect(japanese.contains("移動・改名・削除されません"))
  #expect(SchneeGlassMenuText.resetNoDisplay.resolve(locale: ja).contains("変更されていません"))
  #expect(SchneeGlassMenuText.resetFailed.resolve(locale: ja).contains("変更されていません"))
}
