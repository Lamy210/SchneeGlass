import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedCopyProgressPreservesWorkspaceAndDesktopInformation() {
  let ja = Locale(identifier: "ja_JP")
  let workspace = GlassInteractionPresentation.copying(
    progress: .init(currentIndex: 2, totalCount: 4, currentFilename: "100%_設計.pdf"),
    glassTitle: "開発",
    surface: .workspace,
    locale: ja
  )
  #expect(workspace.indicator == .progress)
  #expect(workspace.title == "開発にコピー中…")
  #expect(workspace.detail == "4件中2件目 · 100%_設計.pdf")
  let desktop = GlassInteractionPresentation.copying(
    progress: .init(currentIndex: 2, totalCount: 4, currentFilename: "100%_設計.pdf"),
    glassTitle: "開発",
    surface: .desktop,
    locale: ja
  )
  #expect(desktop.title == "4件中2件目をコピー中…")
  #expect(desktop.detail == "元のファイルは元の場所に残ります。")
}

@Test
func localizedCopyProgressPreservesUserFilenameAndEnglishFallback() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let filename = "%@.pdf"
  let desktop = GlassInteractionPresentation.copying(
    progress: .init(currentIndex: 1, totalCount: 1, currentFilename: filename),
    glassTitle: "Projects",
    surface: .desktop,
    locale: ja
  )
  #expect(desktop.title == "%@.pdfをコピー中…")
  let english = GlassInteractionPresentation.copying(
    progress: .init(currentIndex: 1, totalCount: 1, currentFilename: filename),
    glassTitle: "Projects",
    surface: .desktop,
    locale: en
  )
  #expect(english.title == "Copying %@.pdf…")
  #expect(english.detail == "Original files stay where they are.")
  #expect(GlassLocalizedText.cancelCopy.resolve(locale: ja) == "コピーをキャンセル")
}

@Test
func localizedCheckingFilesPreservesSurfaceIndicator() {
  let ja = Locale(identifier: "ja_JP")
  let workspace = GlassInteractionPresentation.hovered(surface: .workspace, locale: ja)
  let desktop = GlassInteractionPresentation.hovered(surface: .desktop, locale: ja)
  #expect(workspace.title == "ファイルを確認中…")
  #expect(workspace.indicator == .progress)
  #expect(desktop.title == workspace.title)
  #expect(desktop.indicator == .symbol("ellipsis"))
}
