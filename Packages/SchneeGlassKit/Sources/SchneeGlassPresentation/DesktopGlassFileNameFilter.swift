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
}
