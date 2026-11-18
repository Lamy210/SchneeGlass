import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func workspaceStatusFilterLabelsPreserveEnglishAndUseJapanese() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let expected = ["すべての状態", "接続済み", "空のフォルダ", "読み込み中", "接続不能", "失敗"]
  #expect(WorkspaceGlassStatusFilter.allCases.map { $0.localizedLabel(locale: ja) } == expected)
  for status in WorkspaceGlassStatusFilter.allCases {
    #expect(status.localizedLabel(locale: en) == status.rawValue)
  }
}

@Test
func workspaceSearchSummaryPreservesCountsAndActiveOperationsInBothLanguages() {
  let en = Locale(identifier: "en_US")
  let ja = Locale(identifier: "ja_JP")
  let english = WorkspaceGlassSearch.resultSummary(visible: 2, total: 5, locale: en)
  let japanese = WorkspaceGlassSearch.resultSummary(visible: 2, total: 5, locale: ja)
  #expect(english == "Showing 2 of 5 Glasses. Active operations remain visible.")
  #expect(japanese == "5件中2件のGlassを表示しています。操作中のGlassは引き続き表示されます。")
  let empty = WorkspaceGlassSearch.resultSummary(visible: 0, total: 5, locale: ja)
  #expect(empty.hasPrefix("5件中0件"))
}
