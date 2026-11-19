import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedFolderLoadingAndTruncationKeepTheirDistinctMeaning() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  let loading = GlassLocalizedText.loadingFolder
  let truncated = GlassLocalizedText.workspaceFirst500Items
  #expect(loading.resolve(locale: en) == "Loading folder…")
  #expect(loading.resolve(locale: ja) == "フォルダを読み込み中…")
  #expect(truncated.resolve(locale: en) == "Showing the first 500 items")
  #expect(truncated.resolve(locale: ja) == "最初の500件を表示しています")
  #expect(loading.resolve(locale: fallback) == loading.resolve(locale: en))
  #expect(truncated.resolve(locale: fallback) == truncated.resolve(locale: en))
}
