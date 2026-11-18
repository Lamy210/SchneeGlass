import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func workspaceActionsPreserveEnglishLabelsAndResolveJapanese() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  #expect(GlassLocalizedText.renameGlassMenu.resolve(locale: en) == "Rename Glass…")
  #expect(GlassLocalizedText.renameGlassMenu.resolve(locale: ja) == "Glassの名前を変更…")
  #expect(GlassLocalizedText.refreshFiles.resolve(locale: ja) == "ファイル一覧を更新")
  #expect(GlassLocalizedText.removeGlassAction.resolve(locale: ja) == "Glassを削除")
  #expect(GlassLocalizedText.reconnectOriginalFolder.resolve(locale: ja) == "元のフォルダを再接続…")
}

@Test
func localizedWorkspaceConfirmationPreservesOriginalFileSafetyContract() {
  let ja = Locale(identifier: "ja_JP")
  let en = Locale(identifier: "en_US")
  #expect(GlassLocalizedText.renameGlassDetail.resolve(locale: ja).contains("名前は変更されません"))
  #expect(GlassLocalizedText.removeGlassDetail.resolve(locale: ja).contains("削除・移動されません"))
  #expect(
    GlassLocalizedText.renameGlassDetail.resolve(locale: en).contains("will not be renamed"))
  let removalDetail = GlassLocalizedText.removeGlassDetail.resolve(locale: en)
  #expect(removalDetail.contains("will not be deleted or moved"))
}
