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

@Test
func localizationFormatPlaceholdersRemainCompatibleAcrossLanguages() throws {
  // An accidental translation edit must not change argument types or indexes.
  let expression = try NSRegularExpression(
    pattern: #"%(?:[1-9][0-9]*\$)?(?:hh|h|ll|l|z|t|j|L)?[@diuoxXfFeEgGaAcCsSp%]"#
  )

  func specifiers(in value: String) -> [String] {
    let string = value as NSString
    return expression.matches(
      in: value,
      range: NSRange(location: 0, length: string.length)
    )
    .map { string.substring(with: $0.range) }
    .filter { $0 != "%%" }
    .sorted()
  }

  #expect(specifiers(in: "%% %1$lld and %2$@") == ["%1$lld", "%2$@"])

  var checkedFormatKeys = 0
  for key in GlassLocalizedText.allCases {
    guard let english = key.localizedValue(language: "en"),
      let japanese = key.localizedValue(language: "ja")
    else {
      Issue.record("Missing localized format for \(key.rawValue)")
      continue
    }

    let englishSpecifiers = specifiers(in: english)
    let japaneseSpecifiers = specifiers(in: japanese)
    #expect(englishSpecifiers == japaneseSpecifiers, "Format mismatch: \(key.rawValue)")

    // Multiple argument placeholders must be indexed, so their order can be
    // translated without silently exchanging argument types.
    if englishSpecifiers.count > 1 {
      #expect(
        englishSpecifiers.allSatisfy { $0.contains("$") }, "Unindexed format: \(key.rawValue)")
      #expect(
        japaneseSpecifiers.allSatisfy { $0.contains("$") }, "Unindexed format: \(key.rawValue)")
    }
    if !englishSpecifiers.isEmpty {
      checkedFormatKeys += 1
    }
  }
  #expect(checkedFormatKeys > 0)
}

@Test
func glassCreationAccessibleStatusUsesLocalizedProgressInsteadOfAddAction() {
  let english = Locale(identifier: "en_US")
  let japanese = Locale(identifier: "ja_JP")
  let unsupported = Locale(identifier: "fr_FR")

  #expect(GlassLocalizedText.creatingGlass.resolve(locale: english) == "Creating Glass…")
  #expect(GlassLocalizedText.creatingGlass.resolve(locale: japanese) == "Glassを作成中…")
  #expect(
    GlassLocalizedText.creatingGlass.resolve(locale: unsupported)
      == GlassLocalizedText.creatingGlass.resolve(locale: english))
  #expect(
    GlassLocalizedText.creatingGlass.resolve(locale: english)
      != GlassLocalizedText.addGlass.resolve(locale: english))
  #expect(
    GlassLocalizedText.creatingGlass.resolve(locale: japanese)
      != GlassLocalizedText.addGlass.resolve(locale: japanese))
}

@Test
func restorationIndicatorsRetainLocalizedStatusTextForVoiceOver() {
  let labels: [(GlassLocalizedText, String, String)] = [
    (.restoringStatus, "Restoring…", "復元中…"),
    (.restoringGlasses, "Restoring your Glasses…", "Glassを復元中…"),
  ]
  for (key, english, japanese) in labels {
    #expect(key.resolve(locale: Locale(identifier: "en_US")) == english)
    #expect(key.resolve(locale: Locale(identifier: "ja_JP")) == japanese)
    #expect(key.resolve(locale: Locale(identifier: "fr_FR")) == english)
  }
}
