import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func desktopEmptyStatePreservesEnglishCopyBehaviorAndLocalizesJapanese() {
  let english = DesktopGlassEmptyPresentation.make(locale: Locale(identifier: "en_US"))
  #expect(english.title == "Drop files here")
  #expect(english.detail == "Files are copied. Originals stay where they are.")

  let japanese = DesktopGlassEmptyPresentation.make(locale: Locale(identifier: "ja_JP"))
  #expect(japanese.title == "ここにファイルをドロップ")
  #expect(japanese.detail == "ファイルはコピーされ、元のファイルは元の場所に残ります。")
  #expect(japanese.title != english.title)
  #expect(japanese.detail != english.detail)

  // Unsupported locales intentionally use the existing English fallback contract.
  #expect(DesktopGlassEmptyPresentation.make(locale: Locale(identifier: "fr_FR")) == english)
}

@Test
func desktopEmptyStateCopyGuidanceNeverImpliesMovingOrDeletingSourceFiles() {
  let japanese = DesktopGlassEmptyPresentation.make(locale: Locale(identifier: "ja"))
  let english = DesktopGlassEmptyPresentation.make(locale: Locale(identifier: "en"))
  #expect(japanese.detail.contains("コピー"))
  #expect(japanese.detail.contains("元の場所に残"))
  #expect(english.detail.contains("copied"))
  #expect(english.detail.contains("Originals stay"))
}
