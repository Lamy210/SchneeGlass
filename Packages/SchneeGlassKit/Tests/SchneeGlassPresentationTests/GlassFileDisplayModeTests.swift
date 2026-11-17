import FileDomain
import Foundation
import SchneeGlassApplication
import Testing

@testable import SchneeGlassPresentation

@Test
func glassFileDisplayModeSwitchesBetweenIconsAndList() {
  let grid = GlassFileDisplayMode.grid
  #expect(grid.alternate == .list)
  #expect(grid.alternate.alternate == grid)
  #expect(grid.alternateMenuTitle == "Show as List")
  #expect(grid.alternate.alternateMenuTitle == "Show as Icons")
}

@Test
func glassFileDisplayModeOnlyChangesWhileIdle() {
  #expect(GlassFileDisplayMode.allowsChange(during: .idle))
  #expect(!GlassFileDisplayMode.allowsChange(during: .hovered))
  #expect(!GlassFileDisplayMode.allowsChange(during: .dropInvalid(.collision)))
}

@Test
func displayedItemsKeepIdentitiesWhileCombiningSortAndFilters() {
  let z = displayModeItem("資料-z.txt", kind: .regular)
  let a = displayModeItem("資料-a.txt", kind: .regular)
  let folder = displayModeItem("資料-folder", kind: .directory)
  let other = displayModeItem("notes.txt", kind: .regular)
  let observed = [z, other, folder, a]
  let selected = DesktopGlassDisplayedItems.make(
    observed, sortOrder: .nameAscending, foldersFirst: true,
    query: "資料", kind: .files
  )
  #expect(selected == [a, z])
  #expect(selected.map(\.id) == [a.id, z.id])
  #expect(observed == [z, other, folder, a])
}

@Test
func displayedItemsPreserveSnapshotOrderWithoutSortAndHandleNoMatches() {
  let z = displayModeItem("z.txt", kind: .regular)
  let a = displayModeItem("a.txt", kind: .regular)
  let folder = displayModeItem("folder", kind: .directory)
  let observed = [z, folder, a]
  #expect(
    DesktopGlassDisplayedItems.make(
      observed, sortOrder: nil, foldersFirst: false, query: "", kind: .all
    ) == observed
  )
  #expect(
    DesktopGlassDisplayedItems.make(
      observed, sortOrder: nil, foldersFirst: true, query: "", kind: .all
    ) == [folder, z, a]
  )
  #expect(
    DesktopGlassDisplayedItems.make(
      observed, sortOrder: nil, foldersFirst: false, query: "unobserved", kind: .all
    ).isEmpty
  )
}

private func displayModeItem(_ name: String, kind: FileKind) -> GlassItem {
  let url = URL(fileURLWithPath: "/tmp/SchneeGlassDisplayModeTests").appendingPathComponent(name)
  return GlassItem(
    id: FileIdentity(resourceIdentifier: "display-mode-\(name)", standardizedURL: url),
    url: url,
    displayName: name,
    kind: kind,
    isHidden: false
  )
}
