import FileDomain
import SchneeGlassApplication

/// A temporary presentation choice, independent of file authority or persistence.
enum GlassFileDisplayMode: Equatable {
  case grid
  case list

  var alternate: Self {
    switch self {
    case .grid: return .list
    case .list: return .grid
    }
  }

  var alternateMenuTitle: String {
    switch self {
    case .grid: return "Show as List"
    case .list: return "Show as Icons"
    }
  }

  static func allowsChange(during state: InteractionState) -> Bool {
    if case .idle = state {
      return true
    }
    return false
  }
}

/// Both display modes consume exactly the same ordered, filtered observed items.
/// No fresh enumeration, mutation, or reconstruction of item identity.
enum DesktopGlassDisplayedItems {
  static func make(
    _ items: [GlassItem],
    sortOrder: DesktopGlassFileSortOrder?,
    foldersFirst: Bool,
    query: String,
    kind: DesktopGlassFileKindFilter
  ) -> [GlassItem] {
    let ordered: [GlassItem]
    if let sortOrder {
      ordered = sortOrder.sortedItems(items, foldersFirst: foldersFirst)
    } else if foldersFirst {
      let directories = items.filter { $0.kind == .directory }
      let remaining = items.filter { $0.kind != .directory }
      ordered = directories + remaining
    } else {
      ordered = items
    }
    return DesktopGlassFileNameFilter.matchingItems(ordered, query: query, kind: kind)
  }
}
