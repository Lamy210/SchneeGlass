import FileDomain
import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassPresentation

private func filterItem(
  _ name: String,
  kind: FileKind = .regular,
  path: String? = nil
) -> GlassItem {
  let url = URL(fileURLWithPath: path ?? "/tmp/\(name)")
  return GlassItem(
    id: FileIdentity(resourceIdentifier: url.path, standardizedURL: url),
    url: url,
    displayName: name,
    kind: kind,
    isHidden: false
  )
}

@Test
func emptyOrWhitespaceFilterPreservesAllLoadedItemsAndTheirOrder() {
  let files = [filterItem("z.txt"), filterItem("a.txt")]

  #expect(DesktopGlassFileNameFilter.matchingItems(files, query: "") == files)
  #expect(DesktopGlassFileNameFilter.matchingItems(files, query: " \n\t ") == files)
}

@Test
func filenameFilterIgnoresCaseAndDiacritics() {
  let files = [filterItem("Résumé.PDF"), filterItem("Other.txt")]

  let result = DesktopGlassFileNameFilter.matchingItems(files, query: "  resume  ")

  #expect(result.map(\.displayName) == ["Résumé.PDF"])
}

@Test
func filenameFilterMatchesDirectoryAndPackageDisplayNames() {
  let files = [
    filterItem("Docs", kind: .directory),
    filterItem("Docs.app", kind: .package),
    filterItem("Other.txt"),
  ]

  let result = DesktopGlassFileNameFilter.matchingItems(files, query: "docs")

  #expect(result.map(\.displayName) == ["Docs", "Docs.app"])
}

@Test
func filenameFilterDoesNotSearchSourcePaths() {
  let files = [
    filterItem("notes.txt", path: "/tmp/confidential/notes.txt"),
    filterItem("confidential-report.txt"),
  ]

  let result = DesktopGlassFileNameFilter.matchingItems(files, query: "confidential")

  #expect(result.map(\.displayName) == ["confidential-report.txt"])
}

@Test
func filenameFilterPreservesSelectedSortAndItemIdentities() {
  let files = [
    filterItem("z-report.txt"),
    filterItem("other.txt"),
    filterItem("a-report.txt"),
  ]
  let sorted = DesktopGlassFileSortOrder.nameAscending.sortedItems(files)

  let result = DesktopGlassFileNameFilter.matchingItems(sorted, query: "report")

  #expect(result.map(\.displayName) == ["a-report.txt", "z-report.txt"])
  #expect(result.map(\.id) == [sorted[0].id, sorted[2].id])
  #expect(files.map(\.displayName) == ["z-report.txt", "other.txt", "a-report.txt"])
}

@Test
func filenameFilterSupportsJapaneseDisplayNames() {
  let files = [
    filterItem("開発仕様書.md"),
    filterItem("設計ノート.txt"),
    filterItem("ReleaseNotes.txt"),
  ]

  let result = DesktopGlassFileNameFilter.matchingItems(files, query: "仕様")

  #expect(result.map(\.displayName) == ["開発仕様書.md"])
}

@Test
func filenameFilterReturnsNoMatchesWithoutReadingOutsideTheSnapshot() {
  let firstPage = [filterItem("first.txt"), filterItem("second.txt")]

  let result = DesktopGlassFileNameFilter.matchingItems(firstPage, query: "missing")

  #expect(result.isEmpty)
  #expect(firstPage.count == 2)
}
