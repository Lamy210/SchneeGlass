import FileDomain
import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassPresentation

private func sortItem(
  name: String,
  path: String,
  kind: FileKind = .regular,
  modified: Date? = nil,
  size: Int64? = nil
) -> GlassItem {
  let url = URL(fileURLWithPath: path)
  return GlassItem(
    id: FileIdentity(resourceIdentifier: path, standardizedURL: url),
    url: url,
    displayName: name,
    kind: kind,
    modificationDate: modified,
    fileSize: size,
    isHidden: false
  )
}

@Test
func nameSortUsesFinderStyleOrderingAndStablePathTieBreak() {
  let firstDuplicate = sortItem(name: "alpha", path: "/tmp/a-alpha")
  let secondDuplicate = sortItem(name: "alpha", path: "/tmp/z-alpha")
  let items = [
    sortItem(name: "file10", path: "/tmp/file10"),
    secondDuplicate,
    sortItem(name: "file2", path: "/tmp/file2"),
    firstDuplicate,
  ]

  let sorted = DesktopGlassFileSortOrder.nameAscending.sortedItems(items)

  #expect(sorted.map(\.displayName) == ["alpha", "alpha", "file2", "file10"])
  #expect(sorted[0].id == firstDuplicate.id)
  #expect(sorted[1].id == secondDuplicate.id)
}

@Test
func modifiedSortPlacesNewestFirstAndUnknownDatesLast() {
  let old = sortItem(
    name: "old",
    path: "/tmp/old",
    modified: Date(timeIntervalSince1970: 10)
  )
  let newestB = sortItem(
    name: "b-new",
    path: "/tmp/b-new",
    modified: Date(timeIntervalSince1970: 30)
  )
  let newestA = sortItem(
    name: "a-new",
    path: "/tmp/a-new",
    modified: Date(timeIntervalSince1970: 30)
  )
  let unknown = sortItem(name: "unknown", path: "/tmp/unknown")

  let sorted = DesktopGlassFileSortOrder.modifiedNewest.sortedItems([
    unknown,
    old,
    newestB,
    newestA,
  ])

  #expect(sorted.map(\.displayName) == ["a-new", "b-new", "old", "unknown"])
}

@Test
func sizeSortPlacesLargestFirstAndUnknownSizesLast() {
  let small = sortItem(name: "small", path: "/tmp/small", size: 10)
  let largeB = sortItem(name: "b-large", path: "/tmp/b-large", size: 100)
  let largeA = sortItem(name: "a-large", path: "/tmp/a-large", size: 100)
  let unknown = sortItem(name: "unknown", path: "/tmp/unknown")

  let sorted = DesktopGlassFileSortOrder.sizeLargest.sortedItems([
    small,
    unknown,
    largeB,
    largeA,
  ])

  #expect(sorted.map(\.displayName) == ["a-large", "b-large", "small", "unknown"])
}

@Test
func sortingPreservesOriginalGlassItemIdentityAndInputSnapshotOrder() {
  let alpha = sortItem(name: "alpha", path: "/tmp/alpha", size: 1)
  let beta = sortItem(name: "beta", path: "/tmp/beta", size: 2)
  let input = [alpha, beta]

  let sorted = DesktopGlassFileSortOrder.sizeLargest.sortedItems(input)

  #expect(input.map(\.id) == [alpha.id, beta.id])
  #expect(sorted.map(\.id) == [beta.id, alpha.id])
}

@Test
func foldersFirstGroupsDirectoriesBeforeFilesWhileKeepingSelectedSort() {
  let directory = sortItem(
    name: "z-folder",
    path: "/tmp/z-folder",
    kind: .directory,
    size: 1
  )
  let largeFile = sortItem(
    name: "a-large",
    path: "/tmp/a-large",
    size: 100
  )
  let smallFile = sortItem(
    name: "b-small",
    path: "/tmp/b-small",
    size: 10
  )

  let sorted = DesktopGlassFileSortOrder.sizeLargest.sortedItems(
    [smallFile, largeFile, directory],
    foldersFirst: true
  )

  #expect(sorted.map(\.id) == [directory.id, largeFile.id, smallFile.id])
}

@Test
func foldersFirstDoesNotPromotePackagesOrAliasesToDirectoryGroup() {
  let directory = sortItem(
    name: "z-directory",
    path: "/tmp/z-directory",
    kind: .directory
  )
  let package = sortItem(
    name: "a-package",
    path: "/tmp/a-package",
    kind: .package
  )
  let alias = sortItem(
    name: "b-alias",
    path: "/tmp/b-alias",
    kind: .alias
  )

  let sorted = DesktopGlassFileSortOrder.nameAscending.sortedItems(
    [package, alias, directory],
    foldersFirst: true
  )

  #expect(sorted.map(\.id) == [directory.id, package.id, alias.id])
}

@Test
func disablingFoldersFirstUsesPureSelectedSortOrder() {
  let directory = sortItem(
    name: "z-folder",
    path: "/tmp/z-folder",
    kind: .directory
  )
  let file = sortItem(name: "a-file", path: "/tmp/a-file")

  let sorted = DesktopGlassFileSortOrder.nameAscending.sortedItems(
    [directory, file],
    foldersFirst: false
  )

  #expect(sorted.map(\.id) == [file.id, directory.id])
}
