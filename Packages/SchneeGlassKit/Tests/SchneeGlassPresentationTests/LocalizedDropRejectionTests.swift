import FileDomain
import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedDropRejectionPreservesSurfaceSpecificDetailAvailability() {
  let reasons: [DropRejection] = [
    .unsupportedFolder, .unsupportedPackage, .unsupportedSymbolicLink,
    .unsupportedItem, .tooManyItems(maximum: 20), .collision,
    .containsSameDirectoryItem, .destinationUnavailable, .destinationReadOnly,
    .destinationCopySafetyUnsupported, .networkDestinationUnsupported,
    .sourceUnavailable, .sourceCapacityReached(maximum: 64), .cloudPlaceholderUnavailable,
  ]
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en")
  for reason in reasons {
    for surface in [GlassInteractionPresentationSurface.workspace, .desktop] {
      let japanese = GlassInteractionPresentation.dropInvalid(
        reason: reason, glassTitle: "Projects", surface: surface, locale: ja)
      let english = GlassInteractionPresentation.dropInvalid(
        reason: reason, glassTitle: "Projects", surface: surface, locale: en)
      #expect(japanese.indicator == english.indicator)
      #expect(japanese.title != english.title)
      #expect((japanese.detail == nil) == (english.detail == nil))
    }
  }
}

@Test
func localizedDropRejectionPreservesSafetyAndRecoveryGuidance() {
  let ja = Locale(identifier: "ja_JP")
  let collision = GlassInteractionPresentation.dropInvalid(
    reason: .collision, glassTitle: "Projects", surface: .desktop, locale: ja)
  #expect(collision.detail == "ファイルは上書きされません。")
  let unavailable = GlassInteractionPresentation.dropInvalid(
    reason: .destinationUnavailable, glassTitle: "Projects", surface: .workspace, locale: ja)
  #expect(unavailable.detail?.contains("元のフォルダを再接続") == true)
  #expect(unavailable.detail?.contains("ファイル一覧を更新") == true)
  #expect(unavailable.detail?.contains("削除") == false)
  let cloud = GlassInteractionPresentation.dropInvalid(
    reason: .cloudPlaceholderUnavailable, glassTitle: "Projects", surface: .desktop, locale: ja)
  #expect(cloud.detail?.contains("開始しません") == true)
}

@Test
func localizedDropRejectionPreservesLimitsAndUserSuppliedNames() {
  let ja = Locale(identifier: "ja_JP")
  let limit = GlassInteractionPresentation.dropInvalid(
    reason: .tooManyItems(maximum: 20), glassTitle: "Projects", surface: .workspace, locale: ja)
  #expect(limit.detail?.contains("20件") == true)
  let capacity = GlassInteractionPresentation.dropInvalid(
    reason: .sourceCapacityReached(maximum: 64),
    glassTitle: "Projects", surface: .desktop, locale: ja)
  #expect(capacity.detail?.contains("64件") == true)
  let same = GlassInteractionPresentation.dropInvalid(
    reason: .containsSameDirectoryItem, glassTitle: "100%_開発", surface: .desktop, locale: ja)
  #expect(same.title == "既に100%_開発内にあります")
  #expect(same.detail == nil)
}
