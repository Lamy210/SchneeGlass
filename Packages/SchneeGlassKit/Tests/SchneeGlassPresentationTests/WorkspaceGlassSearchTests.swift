import FileDomain
import Foundation
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

@Test
func workspaceGlassSearchCombinesNameAndStatusFilters() {
  let snapshot = FolderSnapshot(
    folderIdentity: FolderIdentity(
      resourceIdentifier: "status-filter-fixture",
      standardizedURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ),
    items: [],
    isTruncated: false,
    observedAt: Date(timeIntervalSince1970: 1_700_000_000),
    generation: 1
  )
  let ready = searchEntry("Project A", contentState: .ready(snapshot))
  let empty = searchEntry("Project B", contentState: .empty(snapshot))
  let loading = searchEntry("Project C")
  let unavailable = searchEntry("Project D", contentState: .unavailable(.volumeUnavailable))
  let other = searchEntry("Archive", contentState: .unavailable(.sourceMissing))
  let failed = searchEntry("Project E", contentState: .failed(.enumerationFailed))
  let entries = [ready, empty, loading, unavailable, other, failed]
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "", status: .all) == entries)
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "", status: .connected) == [ready])
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "", status: .empty) == [empty])
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "", status: .loading) == [loading])
  #expect(
    WorkspaceGlassSearch.matchingEntries(entries, query: "", status: .unavailable)
      == [unavailable, other])
  #expect(WorkspaceGlassSearch.matchingEntries(entries, query: "", status: .failed) == [failed])
  #expect(
    WorkspaceGlassSearch.matchingEntries(entries, query: "project", status: .unavailable)
      == [unavailable])
  #expect(
    WorkspaceGlassSearch.matchingEntries(entries, query: "archive", status: .failed).isEmpty)
}

@Test
func workspaceGlassStatusFilterKeepsActiveInteractionsVisible() {
  let idle = searchEntry("Archive")
  let copying = searchEntry(
    "Backup",
    interaction: .copying(.init(currentIndex: 1, totalCount: 2, currentFilename: "sample.txt"))
  )
  let entries = [idle, copying]
  for status in WorkspaceGlassStatusFilter.allCases {
    #expect(
      WorkspaceGlassSearch.matchingEntries(entries, query: "missing", status: status)
        == [copying])
  }
  #expect(
    WorkspaceGlassSearch.matchingEntries(entries, query: "", status: .failed)
      == [copying])
}

private func searchEntry(
  _ title: String,
  contentState: GlassContentState = .loading,
  interaction: InteractionState = .idle
) -> GlassWorkspaceEntry {
  GlassWorkspaceEntry(
    id: GlassID(), title: title, contentState: contentState, interactionState: interaction)
}
