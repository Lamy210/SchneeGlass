import FileDomain
import Foundation
import Testing

@testable import SchneeGlassPresentation

@Test
func listMetadataDisplaysObservedRegularFileSizeAndModificationDate() {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let item = listMetadataItem(kind: .regular, size: 1024, date: date)
  let metadata = GlassListItemMetadata.make(for: item)
  let size = ByteCountFormatter.string(fromByteCount: 1024, countStyle: .file)
  let modified = date.formatted(date: .abbreviated, time: .shortened)
  #expect(metadata.size == size)
  #expect(metadata.modified == modified)
  #expect(metadata.displayText == "\(size) · \(modified)")
  #expect(metadata.accessibilityText == "Size: \(size), Modified: \(modified)")
}

@Test
func listMetadataDistinguishesZeroSizeFromUnknownOrInvalidSize() {
  let emptyFile = listMetadataItem(kind: .regular, size: 0)
  let empty = GlassListItemMetadata.make(for: emptyFile)
  #expect(empty.size != nil)
  #expect(empty.modified == nil)
  #expect(empty.displayText == empty.size)
  for size in [nil, -1] as [Int64?] {
    let metadata = GlassListItemMetadata.make(for: listMetadataItem(kind: .regular, size: size))
    #expect(metadata.displayText == nil)
    #expect(metadata.accessibilityText.isEmpty)
  }
}

@Test
func listMetadataNeverDisplaysNonRegularItemSizeAsTargetOrRecursiveSize() {
  let date = Date(timeIntervalSince1970: 1_700_000_000)
  let kinds: [FileKind] = [.directory, .package, .alias, .symbolicLink, .unsupported]
  for kind in kinds {
    let metadata = GlassListItemMetadata.make(
      for: listMetadataItem(kind: kind, size: 2048, date: date)
    )
    #expect(metadata.size == nil)
    #expect(metadata.displayText == metadata.modified)
    #expect(metadata.modified == date.formatted(date: .abbreviated, time: .shortened))
    #expect(!metadata.accessibilityText.contains("Size:"))
  }
}

private func listMetadataItem(
  kind: FileKind,
  size: Int64?,
  date: Date? = nil
) -> GlassItem {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassListMetadataTests/Example")
  return GlassItem(
    id: FileIdentity(resourceIdentifier: "metadata-fixture", standardizedURL: url),
    url: url,
    displayName: "Example",
    kind: kind,
    modificationDate: date,
    fileSize: size,
    isHidden: false
  )
}
