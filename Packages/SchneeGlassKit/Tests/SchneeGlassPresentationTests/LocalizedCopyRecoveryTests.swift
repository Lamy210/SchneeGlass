import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedCopyRecoveryLabelsHaveJapaneseAndEnglishFallback() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let unsupported = Locale(identifier: "fr_FR")
  for key in SchneeGlassCopyRecoveryText.allCases {
    #expect(!key.resolve(locale: en).isEmpty)
    #expect(key.resolve(locale: ja) != key.resolve(locale: en))
    #expect(key.resolve(locale: unsupported) == key.resolve(locale: en))
  }
}

@Test
func localizedMetadataDiscardDoesNotImplyFileDeletion() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let filename = "%@_設計.pdf"
  let japanese = SchneeGlassCopyRecoveryText.discardConfirmation(filename: filename, locale: ja)
  let english = SchneeGlassCopyRecoveryText.discardConfirmation(filename: filename, locale: en)
  #expect(japanese.contains(filename))
  #expect(english.contains(filename))
  #expect(japanese.contains("最終ファイルや未完了ステージングファイル"))
  #expect(japanese.contains("削除・改名・移動・上書きは行いません"))
  #expect(english.contains("does not delete, rename, move, or overwrite"))
}

@Test
func localizedStagingRemovalPreservesIdentityVerificationAndFinalFile() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  let filename = "100%_設計.pdf"
  let japanese = SchneeGlassCopyRecoveryText.removeConfirmation(filename: filename, locale: ja)
  let english = SchneeGlassCopyRecoveryText.removeConfirmation(filename: filename, locale: en)
  #expect(japanese.contains(filename))
  #expect(english.contains(filename))
  #expect(japanese.contains("SchneeGlass所有の未完了ステージングファイルだけ"))
  #expect(japanese.contains("操作ID・ファイル種別・コピー先"))
  #expect(japanese.contains("最終ファイルは削除・上書きされません"))
  #expect(english.contains("revalidate the operation ID, file type, destination"))
  #expect(english.contains("will not be deleted or overwritten"))
}
