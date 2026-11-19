import FileDomain
import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func localizedFileTileLabelsKeepOriginalNameAndFileKind() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  let name = "資料 %1$@.txt"
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassPresentationTests/Example")
  let cases: [(FileKind, String)] = [
    (.directory, "フォルダ、"),
    (.package, "パッケージ、"),
    (.alias, "エイリアス、"),
    (.symbolicLink, "シンボリックリンク、"),
    (.regular, ""),
    (.unsupported, ""),
  ]
  for (kind, prefix) in cases {
    let item = GlassItem(
      id: FileIdentity(resourceIdentifier: "localized-tile", standardizedURL: url),
      url: url,
      displayName: name,
      kind: kind,
      modificationDate: nil,
      fileSize: nil,
      isHidden: false
    )
    let english = GlassItemPresentation.make(for: item, locale: en)
    let japanese = GlassItemPresentation.make(for: item, locale: ja)
    #expect(japanese.accessibilityLabel == prefix + name)
    #expect(japanese.systemImage == english.systemImage)
    #expect(GlassItemPresentation.make(for: item, locale: fallback) == english)
  }
}

@Test
func localizedFileTileActionsAndMetadataPreserveMissingValues() {
  let en = Locale(identifier: "en")
  let ja = Locale(identifier: "ja_JP")
  let fallback = Locale(identifier: "fr_FR")
  #expect(GlassLocalizedText.tileOpen.resolve(locale: ja) == "開く")
  #expect(GlassLocalizedText.tileReveal.resolve(locale: ja) == "Finderに表示")
  #expect(GlassLocalizedText.tileOpenHint.resolve(locale: ja) == "項目を開きます")
  let metadata = GlassListItemMetadata(size: "1 KB", modified: "2026-11-20")
  #expect(metadata.accessibilityText(locale: ja) == "サイズ：1 KB, 更新日時：2026-11-20")
  #expect(metadata.accessibilityText(locale: fallback) == metadata.accessibilityText(locale: en))
  let missing = GlassListItemMetadata(size: nil, modified: nil)
  #expect(missing.accessibilityText(locale: ja).isEmpty)
  let dateOnly = GlassListItemMetadata(size: nil, modified: "2026-11-20")
  #expect(dateOnly.accessibilityText(locale: ja) == "更新日時：2026-11-20")
}
