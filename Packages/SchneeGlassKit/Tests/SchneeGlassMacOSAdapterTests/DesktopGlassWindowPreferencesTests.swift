import Foundation
import SchneeGlassDomain
import Testing

@testable import SchneeGlassMacOSAdapter

@Test
func positionLockPersistsAcrossStoreInstances() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let firstStore = DesktopGlassWindowPreferences(defaults: defaults)

  #expect(!firstStore.isPositionLocked(for: glassID))
  firstStore.setPositionLocked(true, for: glassID)
  #expect(firstStore.isPositionLocked(for: glassID))

  let restoredStore = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(restoredStore.isPositionLocked(for: glassID))
}

@Test
func unlockingOneGlassDoesNotAffectAnotherGlass() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let firstID = GlassID()
  let secondID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  store.setPositionLocked(true, for: firstID)
  store.setPositionLocked(true, for: secondID)
  store.setPositionLocked(false, for: firstID)

  #expect(!store.isPositionLocked(for: firstID))
  #expect(store.isPositionLocked(for: secondID))
}

@Test
func malformedStoredIdentifiersAreIgnored() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  defaults.set(
    ["not-a-uuid", glassID.rawValue.uuidString],
    forKey: "desktopGlass.lockedPositionIDs.v1"
  )

  let store = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(store.isPositionLocked(for: glassID))
}

@Test
func removingPositionLockClearsPersistedState() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setPositionLocked(true, for: glassID)
  store.removePositionLock(for: glassID)

  #expect(!store.isPositionLocked(for: glassID))
  #expect(defaults.object(forKey: "desktopGlass.lockedPositionIDs.v1") == nil)
}
