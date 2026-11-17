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

@Test
func filterStatusReportsOnlyLoadedMatches() {
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: "report",
      loadedCount: 500,
      matchingCount: 0,
      isTruncated: true
    ) == "0 of 500 loaded items match. More items are not searched."
  )
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: "report",
      loadedCount: 500,
      matchingCount: 500,
      isTruncated: true
    ) == "500 of 500 loaded items match. More items are not searched."
  )
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: "report",
      loadedCount: 2,
      matchingCount: 1,
      isTruncated: false
    ) == "1 of 2 loaded items match."
  )
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: "missing",
      loadedCount: 2,
      matchingCount: 0,
      isTruncated: false
    ) == "0 of 2 loaded items match."
  )
}

@Test
func filterStatusForBlankQueryOnlyShowsTruncation() {
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: " \t\n ",
      loadedCount: 500,
      matchingCount: 500,
      isTruncated: true
    ) == "Showing 500 loaded items. More items exist."
  )
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: "",
      loadedCount: 500,
      matchingCount: 500,
      isTruncated: false
    ) == nil
  )
}

@Test
func kindFilterSeparatesEveryObservedFileKind() {
  let items = [
    filterItem("Report.txt"),
    filterItem("Report", kind: .directory),
    filterItem("Report.app", kind: .package),
    filterItem("Report alias", kind: .alias),
    filterItem("Report link", kind: .symbolicLink),
    filterItem("Report other", kind: .unsupported),
  ]
  let expected: [(DesktopGlassFileKindFilter, [GlassItem])] = [
    (.all, items),
    (.files, [items[0]]),
    (.folders, [items[1]]),
    (.packages, [items[2]]),
    (.links, [items[3], items[4]]),
    (.other, [items[5]]),
  ]
  for (kind, matches) in expected {
    #expect(DesktopGlassFileNameFilter.matchingItems(items, query: " ", kind: kind) == matches)
  }
}

@Test
func combinedNameAndKindFilterPreservesOrderAndIdentities() {
  let items = [
    filterItem("資料-z", kind: .alias),
    filterItem("資料.txt"),
    filterItem("other", kind: .symbolicLink),
    filterItem("資料-a", kind: .symbolicLink),
  ]
  let matches = DesktopGlassFileNameFilter.matchingItems(items, query: "資料", kind: .links)
  #expect(matches == [items[0], items[3]])
  #expect(matches.map(\.id) == [items[0].id, items[3].id])
  #expect(DesktopGlassFileNameFilter.matchingItems(items, query: "missing", kind: .links).isEmpty)
  #expect(DesktopGlassFileNameFilter.matchingItems(items, query: "", kind: .all) == items)
}

@Test
func kindOnlyFilterReportsLoadedSelectionAndTruncation() {
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: "",
      loadedCount: 500,
      matchingCount: 0,
      isTruncated: true,
      kind: .folders
    ) == "0 of 500 loaded items match. More items are not searched."
  )
  #expect(
    DesktopGlassFileNameFilter.statusText(
      query: "",
      loadedCount: 5,
      matchingCount: 2,
      isTruncated: false,
      kind: .links
    ) == "2 of 5 loaded items match."
  )
}
