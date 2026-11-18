import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func desktopFilterLabelsPreserveEnglishAndUseJapanese() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let expected = ["すべての種類", "ファイル", "フォルダ", "パッケージ", "リンクとエイリアス", "その他"]
  #expect(DesktopGlassFileKindFilter.allCases.map { $0.localizedLabel(locale: ja) } == expected)
  for kind in DesktopGlassFileKindFilter.allCases {
    #expect(kind.localizedLabel(locale: en) == kind.rawValue)
  }
}

@Test
func desktopDisplayModeAlternateActionPreservesDirectionInBothLanguages() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  for mode in [GlassFileDisplayMode.grid, .list] {
    #expect(mode.localizedAlternateMenuTitle(locale: en) == mode.alternateMenuTitle)
  }
  #expect(GlassFileDisplayMode.grid.localizedAlternateMenuTitle(locale: ja) == "リスト表示")
  #expect(GlassFileDisplayMode.list.localizedAlternateMenuTitle(locale: ja) == "アイコン表示")
}
