import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func contentStatusUsesJapaneseWithoutChangingItsSymbol() {
  let japanese = Locale(identifier: "ja_JP")
  let english = Locale(identifier: "en_US")
  let localized = GlassContentStatusPresentation.make(
    for: .unavailable(.volumeUnavailable), locale: japanese)
  let original = GlassContentStatusPresentation.make(
    for: .unavailable(.volumeUnavailable), locale: english)
  #expect(localized?.label == "接続不能")
  #expect(localized?.systemImage == original?.systemImage)
  #expect(GlassContentStatusPresentation.make(for: .loading, locale: japanese) == nil)
}

@Test
func contentFailureAndReconnectGuidanceUseTheSameLocale() {
  let locale = Locale(identifier: "ja_JP")
  let transient = GlassContentFailurePresentation.make(for: .enumerationFailed, locale: locale)
  let unexpected = GlassContentFailurePresentation.make(for: .unexpected, locale: locale)
  let unavailable = GlassUnavailablePresentation.make(locale: locale)
  #expect(transient.status == "更新に失敗")
  #expect(transient.detail.contains("再試行"))
  #expect(unexpected.status == "確認が必要")
  #expect(unavailable.title == "フォルダに接続できません")
  #expect(unavailable.detail.contains("元のフォルダを再接続"))
  #expect(unavailable.detail.contains("Glassを削除せず"))
  #expect(
    GlassContentStatusPresentation.make(for: .failed(.enumerationFailed), locale: locale)?
      .label == transient.status)
}

@Test
func contentPresentationPreservesEnglishForUnsupportedLocale() {
  let french = Locale(identifier: "fr_FR")
  let english = Locale(identifier: "en")
  #expect(
    GlassUnavailablePresentation.make(locale: french)
      == GlassUnavailablePresentation.make(locale: english))
  #expect(
    GlassContentFailurePresentation.make(for: .unexpected, locale: french)
      == GlassContentFailurePresentation.make(for: .unexpected, locale: english))
}
