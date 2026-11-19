import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func copyRecoveryMessagesHaveJapaneseAndEnglishFallback() {
  let keys = GlassLocalizedText.allCases.filter { $0.rawValue.hasPrefix("recoveryMessage") }
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  #expect(keys.count == 43)
  for key in keys {
    #expect(key.localizedValue(language: "ja") != nil)
    #expect(key.localizedValue(language: "en") != nil)
    #expect(key.resolve(locale: ja) != key.resolve(locale: en))
    #expect(key.resolve(locale: fallback) == key.resolve(locale: en))
  }
}

@MainActor
@Test
func copyRecoveryErrorMessagesPreserveSafetyAndRecoveryGuidance() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let mutation = PendingCopyRecoveryCenterModel.messageKey(
    for: PendingCopyRecoveryCenterError.mutationFailed)
  #expect(mutation.resolve(locale: ja).contains("最終ファイルは削除・上書きされていません"))
  let expected =
    "SchneeGlass couldn't complete that recovery mutation safely. "
    + "Final user-visible files were not deleted or overwritten."
  #expect(mutation.resolve(locale: en) == expected)
  let mismatch = PendingCopyRecoveryCenterModel.messageKey(
    for: PendingCopyDestinationReconnectError.selectedDestinationMismatch)
  #expect(mismatch.resolve(locale: ja).contains("既存のコピー先を保持"))
  let stale = PendingCopyRecoveryCenterModel.messageKey(
    for: PendingCopyRecoveryNavigationError.actionNoLongerAvailable)
  #expect(stale.resolve(locale: ja).contains("復旧一覧を更新"))
  #expect(stale.resolve(locale: ja).contains("最新の状態"))
}
