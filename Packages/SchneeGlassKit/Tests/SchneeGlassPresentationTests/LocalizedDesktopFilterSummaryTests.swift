import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func desktopFilterLocalizedSummaryDistinguishesLoadedItemsFromWholeFolder() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let japanese = DesktopGlassFileNameFilter.statusText(
    query: "missing", loadedCount: 500, matchingCount: 0, isTruncated: true, locale: ja)
  let english = DesktopGlassFileNameFilter.statusText(
    query: "missing", loadedCount: 500, matchingCount: 0, isTruncated: true, locale: en)
  #expect(japanese == "読み込み済み500件中0件が一致しました。未読み込みの項目は検索対象外です。")
  #expect(english == "0 of 500 loaded items match. More items are not searched.")
}

@Test
func desktopFilterLocalizedSummaryCoversKindOnlyAndUnfilteredSnapshots() {
  let ja = Locale(identifier: "ja_JP")
  let kindOnly = DesktopGlassFileNameFilter.statusText(
    query: "", loadedCount: 5, matchingCount: 2, isTruncated: false, kind: .folders, locale: ja)
  #expect(kindOnly == "読み込み済み5件中2件が一致しました。")
  let truncated = DesktopGlassFileNameFilter.statusText(
    query: "", loadedCount: 500, matchingCount: 500, isTruncated: true, locale: ja)
  #expect(truncated == "読み込み済みの500件を表示しています。ほかにも項目があります。")
  let complete = DesktopGlassFileNameFilter.statusText(
    query: " ", loadedCount: 5, matchingCount: 5, isTruncated: false, locale: ja)
  #expect(complete == nil)
}
