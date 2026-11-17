import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassPresentation

@Test
func workspaceGlassSearchReturnsOriginalEntriesForBlankQuery() {
  let entries = [searchEntry("Projects"), searchEntry("資料")]
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "") == entries)
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: " \n\t") == entries)
  #expect(WorkspaceGlassSearch.matchingEntries([], query: "Projects").isEmpty)
}

@Test
func workspaceGlassSearchPreservesOrderAndIdentityOfMatchingEntries() {
  let first = searchEntry("Projects")
  let second = searchEntry("Archive")
  let third = searchEntry("PROJECTS")
  let japanese = searchEntry("開発資料")
  let entries = [first, second, third, japanese]
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: " project ") == [first, third])
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "資料") == [japanese])
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "missing").isEmpty)
}

@Test
func workspaceGlassSearchNeverHidesActiveInteractions() {
  let idle = searchEntry("Archive")
  let hovered = searchEntry("Other", interaction: .hovered)
  let valid = searchEntry("Destination", interaction: .dropValid(.noOperation))
  let invalid = searchEntry("Collision", interaction: .dropInvalid(.collision))
  let copying = searchEntry(
    "Backup",
    interaction: .copying(.init(currentIndex: 1, totalCount: 2, currentFilename: "sample.txt"))
  )
  let entries = [idle, hovered, valid, invalid, copying]
  #expect(
    WorkspaceGlassSearch.matchingEntries(entries, query: "missing")
      == [hovered, valid, invalid, copying])
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "Archive") == entries)
}

private func searchEntry(
  _ title: String,
  interaction: InteractionState = .idle
) -> GlassWorkspaceEntry {
  GlassWorkspaceEntry(
    id: GlassID(), title: title, contentState: .loading, interactionState: interaction)
}
