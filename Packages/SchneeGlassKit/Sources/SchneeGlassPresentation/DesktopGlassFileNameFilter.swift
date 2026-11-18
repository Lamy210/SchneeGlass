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

  func localizedLabel(locale: Locale) -> String {
    let key: GlassLocalizedText
    switch self {
    case .all:
      key = .allTypes
    case .files:
      key = .files
    case .folders:
      key = .folders
    case .packages:
      key = .packages
    case .links:
      key = .linksAndAliases
    case .other:
      key = .otherFileTypes
    }
    return key.resolve(locale: locale)
  }

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

/// A view-local filter session. Refreshes may temporarily remove the search
/// field; restore the query, but never steal focus when the field reappears.
struct DesktopGlassFilterSession {
  private(set) var isVisible = false
  private var requestsFocus = false
  var query = ""
  var kind: DesktopGlassFileKindFilter = .all

  var effectiveQuery: String { isVisible ? query : "" }
  var effectiveKind: DesktopGlassFileKindFilter { isVisible ? kind : .all }

  mutating func open(ifSupported supported: Bool) {
    guard supported, !isVisible else { return }
    isVisible = true
    requestsFocus = true
  }

  mutating func consumeFocusRequest() -> Bool {
    let requested = requestsFocus && isVisible
    requestsFocus = false
    return requested
  }

  mutating func discardFocusRequest() {
    requestsFocus = false
  }

  mutating func close() {
    isVisible = false
    requestsFocus = false
    query = ""
    kind = .all
  }
}
