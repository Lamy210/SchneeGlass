import Foundation

/// Filters the existing Workspace entries without reading the filesystem.
enum WorkspaceGlassSearch {
  static func matchingEntries(
    _ entries: [GlassWorkspaceEntry],
    query: String
  ) -> [GlassWorkspaceEntry] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return entries
    }

    // Keep active interactions and their cancellation/recovery controls visible.
    return entries.filter {
      $0.interactionState != .idle || $0.title.localizedStandardContains(trimmed)
    }
  }
}
