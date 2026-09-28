import Foundation
import SchneeGlassDomain

public final class DesktopGlassWindowPreferences {
  private let defaults: UserDefaults
  private let lockedPositionKey: String
  private let keepOnTopKey: String
  private let opacityKey: String

  public init(
    defaults: UserDefaults = .standard,
    lockedPositionKey: String = "desktopGlass.lockedPositionIDs.v1",
    keepOnTopKey: String = "desktopGlass.keepOnTopIDs.v1",
    opacityKey: String = "desktopGlass.opacityByID.v1"
  ) {
    self.defaults = defaults
    self.lockedPositionKey = lockedPositionKey
    self.keepOnTopKey = keepOnTopKey
    self.opacityKey = opacityKey
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

  public func opacityPreset(for glassID: GlassID) -> DesktopGlassOpacityPreset {
    guard let rawValue = storedOpacityValues()[glassID.rawValue.uuidString],
      let preset = DesktopGlassOpacityPreset(rawValue: rawValue)
    else {
      return .full
    }
    return preset
  }

  public func setOpacityPreset(
    _ preset: DesktopGlassOpacityPreset,
    for glassID: GlassID
  ) {
    var stored = storedOpacityValues()
    if preset == .full {
      stored.removeValue(forKey: glassID.rawValue.uuidString)
    } else {
      stored[glassID.rawValue.uuidString] = preset.rawValue
    }
    persistOpacityValues(stored)
  }

  public func removeOpacityPreset(for glassID: GlassID) {
    var stored = storedOpacityValues()
    guard stored.removeValue(forKey: glassID.rawValue.uuidString) != nil else {
      return
    }
    persistOpacityValues(stored)
  }

  private func storedOpacityValues() -> [String: Double] {
    guard let stored = defaults.dictionary(forKey: opacityKey) else {
      return [:]
    }

    var result: [String: Double] = [:]
    for (key, value) in stored {
      guard UUID(uuidString: key) != nil,
        let number = value as? NSNumber
      else {
        continue
      }
      let rawValue = number.doubleValue
      guard DesktopGlassOpacityPreset(rawValue: rawValue) != nil else {
        continue
      }
      result[key] = rawValue
    }
    return result
  }

  private func persistOpacityValues(_ values: [String: Double]) {
    guard !values.isEmpty else {
      defaults.removeObject(forKey: opacityKey)
      return
    }
    defaults.set(values, forKey: opacityKey)
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
