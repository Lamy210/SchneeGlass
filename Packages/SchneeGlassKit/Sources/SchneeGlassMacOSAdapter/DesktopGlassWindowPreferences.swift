import Foundation
import SchneeGlassDomain

public final class DesktopGlassWindowPreferences {
  private static let defaultLockedPositionKey = "desktopGlass.lockedPositionIDs.v1"

  private let defaults: UserDefaults
  private let lockedPositionKey: String

  public init(
    defaults: UserDefaults = .standard,
    lockedPositionKey: String = Self.defaultLockedPositionKey
  ) {
    self.defaults = defaults
    self.lockedPositionKey = lockedPositionKey
  }

  public func isPositionLocked(for glassID: GlassID) -> Bool {
    lockedPositionIDs().contains(glassID.rawValue)
  }

  public func setPositionLocked(_ isLocked: Bool, for glassID: GlassID) {
    var lockedIDs = lockedPositionIDs()
    if isLocked {
      lockedIDs.insert(glassID.rawValue)
    } else {
      lockedIDs.remove(glassID.rawValue)
    }
    persist(lockedIDs)
  }

  public func removePositionLock(for glassID: GlassID) {
    var lockedIDs = lockedPositionIDs()
    guard lockedIDs.remove(glassID.rawValue) != nil else {
      return
    }
    persist(lockedIDs)
  }

  private func lockedPositionIDs() -> Set<UUID> {
    guard let stored = defaults.array(forKey: lockedPositionKey) as? [String] else {
      return []
    }
    return Set(stored.compactMap(UUID.init(uuidString:)))
  }

  private func persist(_ lockedIDs: Set<UUID>) {
    guard !lockedIDs.isEmpty else {
      defaults.removeObject(forKey: lockedPositionKey)
      return
    }
    defaults.set(
      lockedIDs.map(\.uuidString).sorted(),
      forKey: lockedPositionKey
    )
  }
}
