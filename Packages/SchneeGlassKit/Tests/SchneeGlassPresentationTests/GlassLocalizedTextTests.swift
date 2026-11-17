import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func glassStatusLocalizationResourcesContainEveryKeyInBothLanguages() {
  for key in GlassLocalizedText.allCases {
    for language in ["en", "ja"] {
      let value = key.localizedValue(language: language)
      #expect(value != nil)
      #expect(value?.isEmpty == false)
      #expect(value != key.rawValue)
    }
  }
}

@Test
func glassStatusLocalizationResolvesJapaneseAndEnglishByLanguage() {
  #expect(GlassLocalizedText.connected.resolve(locale: Locale(identifier: "ja_JP")) == "接続済み")
  #expect(GlassLocalizedText.connected.resolve(locale: Locale(identifier: "en_US")) == "Connected")
  #expect(GlassLocalizedText.empty.resolve(locale: Locale(identifier: "ja")) == "空のフォルダ")
  #expect(
    GlassLocalizedText.unavailableTitle.resolve(locale: Locale(identifier: "en_US_POSIX"))
      == "Folder unavailable")
}

@Test
func glassStatusLocalizationFallsBackToEnglishForUnsupportedLocales() {
  for key in GlassLocalizedText.allCases {
    #expect(
      key.resolve(locale: Locale(identifier: "fr_FR"))
        == key.resolve(locale: Locale(identifier: "en")))
    #expect(key.localizedValue(language: "zz") == nil)
  }
}

@Test
func localizedRecoveryGuidancePreservesReconnectAndCopyRecoveryDistinction() {
  let japanese = GlassLocalizedText.unavailableDetail.resolve(locale: Locale(identifier: "ja_JP"))
  #expect(japanese.contains("Glassを削除せず"))
  #expect(japanese.contains("元のフォルダを再接続"))
  #expect(japanese.contains("コピー操作が中断された場合"))
  let english = GlassLocalizedText.unavailableDetail.resolve(locale: Locale(identifier: "en"))
  #expect(english.contains("without removing this Glass"))
  #expect(english.contains("Pending Copy Recovery in Settings is for interrupted copies"))
}
