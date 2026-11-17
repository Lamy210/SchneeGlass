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

  func localizedLabel(locale: Locale) -> String {
    let key: GlassLocalizedText
    switch self {
    case .all:
      key = .allStates
    case .connected:
      key = .connected
    case .empty:
      key = .empty
    case .loading:
      key = .loading
    case .unavailable:
      key = .unavailable
    case .failed:
      key = .failed
    }
    return key.resolve(locale: locale)
  }

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
  static func resultSummary(visible: Int, total: Int, locale: Locale) -> String {
    String(
      format: GlassLocalizedText.workspaceSearchCount.resolve(locale: locale),
      locale: locale,
      Int64(visible), Int64(total)
    )
  }

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
