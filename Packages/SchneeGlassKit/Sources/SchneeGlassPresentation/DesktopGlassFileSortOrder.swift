import FileDomain
import Foundation

public enum DesktopGlassFileSortOrder: String, CaseIterable, Sendable {
  case nameAscending
  case modifiedNewest
  case sizeLargest

  func sortedItems(
    _ items: [GlassItem],
    foldersFirst: Bool = false
  ) -> [GlassItem] {
    items.sorted { lhs, rhs in
      if foldersFirst {
        let lhsIsFolder = lhs.kind == .directory
        let rhsIsFolder = rhs.kind == .directory
        if lhsIsFolder != rhsIsFolder {
          return lhsIsFolder
        }
      }
      return areInIncreasingOrder(lhs, rhs)
    }
  }

  private func areInIncreasingOrder(_ lhs: GlassItem, _ rhs: GlassItem) -> Bool {
    switch self {
    case .nameAscending:
      return compareNames(lhs, rhs)
    case .modifiedNewest:
      return compareOptionalDescending(
        lhs.modificationDate,
        rhs.modificationDate,
        lhs: lhs,
        rhs: rhs
      )
    case .sizeLargest:
      return compareOptionalDescending(
        lhs.fileSize,
        rhs.fileSize,
        lhs: lhs,
        rhs: rhs
      )
    }
  }

  private func compareNames(_ lhs: GlassItem, _ rhs: GlassItem) -> Bool {
    let comparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
    if comparison != .orderedSame {
      return comparison == .orderedAscending
    }
    return lhs.url.standardizedFileURL.path < rhs.url.standardizedFileURL.path
  }

  private func compareOptionalDescending<Value: Comparable>(
    _ lhsValue: Value?,
    _ rhsValue: Value?,
    lhs: GlassItem,
    rhs: GlassItem
  ) -> Bool {
    switch (lhsValue, rhsValue) {
    case (let lhsValue?, let rhsValue?):
      if lhsValue != rhsValue {
        return lhsValue > rhsValue
      }
      return compareNames(lhs, rhs)
    case (_?, nil):
      return true
    case (nil, _?):
      return false
    case (nil, nil):
      return compareNames(lhs, rhs)
    }
  }
}
