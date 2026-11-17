import Foundation
import SchneeGlassApplication

enum WorkspaceGlassStatusFilter: String, CaseIterable, Identifiable {
  case all = "All States"
  case connected = "Connected"
  case empty = "Empty"
  case loading = "Loading"
  case unavailable = "Unavailable"
  case failed = "Failed"

  var id: Self { self }

  func includes(_ state: GlassContentState) -> Bool {
    switch (self, state) {
    case (.all, _), (.connected, .ready), (.empty, .empty), (.loading, .loading),
      (.unavailable, .unavailable), (.failed, .failed):
      return true
    default:
      return false
    }
  }
}

/// Filters the existing Workspace entries without reading the filesystem.
enum WorkspaceGlassSearch {
  static func matchingEntries(
    _ entries: [GlassWorkspaceEntry],
    query: String,
    status: WorkspaceGlassStatusFilter = .all
  ) -> [GlassWorkspaceEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty || status != .all else {
      return entries
    }

    // Active interactions override both filters to retain progress and cancellation.
    return entries.filter {
      $0.interactionState != .idle
        || (status.includes($0.contentState)
          && (trimmed.isEmpty || $0.title.localizedStandardContains(trimmed)))
    }
  }
}
