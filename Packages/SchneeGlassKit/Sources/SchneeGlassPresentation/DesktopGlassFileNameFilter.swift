import FileDomain
import Foundation

enum DesktopGlassFileNameFilter {
  static func matchingItems(_ items: [GlassItem], query: String) -> [GlassItem] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedQuery.isEmpty else {
      return items
    }
    return items.filter { $0.displayName.localizedStandardContains(trimmedQuery) }
  }

  /// Describe only loaded items. A truncated snapshot cannot establish
  /// that a filename does not exist elsewhere in the connected folder.
  static func statusText(
    query: String,
    loadedCount: Int,
    matchingCount: Int,
    isTruncated: Bool
  ) -> String? {
    let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasQuery {
      let count = "\(matchingCount) of \(loadedCount) loaded items match"
      return isTruncated ? count + ". More items are not searched." : count + "."
    }
    if isTruncated {
      return "Showing \(loadedCount) loaded items. More items exist."
    }
    return nil
  }
}
