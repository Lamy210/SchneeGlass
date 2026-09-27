import Foundation
import SchneeGlassDomain

public final class DesktopGlassWindowPreferences {
  private let defaults: UserDefaults
  private let lockedPositionKey: String
  private let keepOnTopKey: String

  public init(
    defaults: UserDefaults = .standard,
    lockedPositionKey: String = "desktopGlass.lockedPositionIDs.v1",
    keepOnTopKey: String = "desktopGlass.keepOnTopIDs.v1"
  ) {
    self.defaults = defaults
    self.lockedPositionKey = lockedPositionKey
    self.keepOnTopKey = keepOnTopKey
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
    persist(lockedIDs, forKey: lockedPositionKey)
  }

  public func removePositionLock(for glassID: GlassID) {
    var lockedIDs = lockedPositionIDs()
    guard lockedIDs.remove(glassID.rawValue) != nil else {
      return
    }
    persist(lockedIDs, forKey: lockedPositionKey)
  }

  public func keepsOnTop(_ glassID: GlassID) -> Bool {
    storedGlassIDs(forKey: keepOnTopKey).contains(glassID.rawValue)
  }

  public func setKeepsOnTop(_ keepsOnTop: Bool, for glassID: GlassID) {
    var glassIDs = storedGlassIDs(forKey: keepOnTopKey)
    if keepsOnTop {
      glassIDs.insert(glassID.rawValue)
    } else {
      glassIDs.remove(glassID.rawValue)
    }
    persist(glassIDs, forKey: keepOnTopKey)
  }

  public func removeKeepOnTop(for glassID: GlassID) {
    var glassIDs = storedGlassIDs(forKey: keepOnTopKey)
    guard glassIDs.remove(glassID.rawValue) != nil else {
      return
    }
    persist(glassIDs, forKey: keepOnTopKey)
  }

  private func lockedPositionIDs() -> Set<UUID> {
    storedGlassIDs(forKey: lockedPositionKey)
  }

  private func storedGlassIDs(forKey key: String) -> Set<UUID> {
    guard let stored = defaults.array(forKey: key) as? [String] else {
      return []
    }
    return Set(stored.compactMap(UUID.init(uuidString:)))
  }

  private func persist(_ glassIDs: Set<UUID>, forKey key: String) {
    guard !glassIDs.isEmpty else {
      defaults.removeObject(forKey: key)
      return
    }
    defaults.set(
      glassIDs.map(\.uuidString).sorted(),
      forKey: key
    )
  }
}
