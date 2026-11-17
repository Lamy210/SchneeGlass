import FileDomain
import Foundation

/// Categories describe the loaded item's observed kind, not its target or extension.
enum DesktopGlassFileKindFilter: String, CaseIterable, Identifiable {
  case all = "All Types"
  case files = "Files"
  case folders = "Folders"
  case packages = "Packages"
  case links = "Links and Aliases"
  case other = "Other"

  var id: Self { self }

  func includes(_ kind: FileKind) -> Bool {
    switch self {
    case .all:
      return true
    case .files:
      return kind == .regular
    case .folders:
      return kind == .directory
    case .packages:
      return kind == .package
    case .links:
      return kind == .alias || kind == .symbolicLink
    case .other:
      return kind == .unsupported
    }
  }
}

enum DesktopGlassFileNameFilter {
  static func matchingItems(
    _ items: [GlassItem],
    query: String,
    kind: DesktopGlassFileKindFilter = .all
  ) -> [GlassItem] {
    let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return items.filter {
      kind.includes($0.kind)
        && (trimmedQuery.isEmpty || $0.displayName.localizedStandardContains(trimmedQuery))
    }
  }

  /// Describe only loaded items. A truncated snapshot cannot establish
  /// that a filename does not exist elsewhere in the connected folder.
  static func statusText(
    query: String,
    loadedCount: Int,
    matchingCount: Int,
    isTruncated: Bool,
    kind: DesktopGlassFileKindFilter = .all
  ) -> String? {
    let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    if hasQuery || kind != .all {
      let count = "\(matchingCount) of \(loadedCount) loaded items match"
      return isTruncated ? count + ". More items are not searched." : count + "."
    }
    if isTruncated {
      return "Showing \(loadedCount) loaded items. More items exist."
    }
    return nil
  }
}
