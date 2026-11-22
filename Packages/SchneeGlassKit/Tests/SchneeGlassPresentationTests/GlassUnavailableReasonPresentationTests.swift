import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func unavailableReasonExplainsEachRecoveryWithoutLeakingSourcePaths() {
  let reasons: [UnavailableReason] = [
    .permissionLost,
    .sourceMissing,
    .volumeUnavailable,
    .bookmarkResolutionFailed,
    .replacementDetected,
    .unsupportedLocation,
  ]
  let locale = Locale(identifier: "en_US")
  let messages = reasons.map { GlassUnavailablePresentation.make(for: $0, locale: locale) }

  #expect(Set(messages.map(\.detail)).count == reasons.count)
  #expect(messages.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
  #expect(messages.allSatisfy { $0.title == "Folder unavailable" })
  #expect(messages[4].detail.contains("will not use it automatically"))
}

@Test
func unavailableReasonUsesJapaneseLocalizedRecoveryGuidance() {
  let locale = Locale(identifier: "ja_JP")
  let volume = GlassUnavailablePresentation.make(for: .volumeUnavailable, locale: locale)
  let replacement = GlassUnavailablePresentation.make(for: .replacementDetected, locale: locale)
  let permission = GlassUnavailablePresentation.make(for: .permissionLost, locale: locale)

  #expect(volume.detail.contains("ドライブ"))
  #expect(replacement.detail.contains("自動的には接続しません"))
  #expect(permission.detail.contains("アクセス許可"))
  #expect(volume.title == "フォルダに接続できません")
  #expect(volume.detail != replacement.detail)
}

@Test
func unavailableReasonUnknownLocaleUsesExistingEnglishFallback() {
  let reason = UnavailableReason.bookmarkResolutionFailed
  let french = GlassUnavailablePresentation.make(for: reason, locale: Locale(identifier: "fr_FR"))
  let english = GlassUnavailablePresentation.make(for: reason, locale: Locale(identifier: "en_US"))
  #expect(french == english)

  let original = GlassUnavailablePresentation.make(locale: Locale(identifier: "en_US"))
  #expect(original.title == english.title)
  #expect(!original.detail.isEmpty)
}
