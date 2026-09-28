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

@Test
func keepOnTopPersistsIndependentlyFromPositionLock() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  store.setKeepsOnTop(true, for: glassID)

  let restoredStore = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(restoredStore.keepsOnTop(glassID))
  #expect(!restoredStore.isPositionLocked(for: glassID))
}

@Test
func removingKeepOnTopClearsOnlyKeepOnTopPreference() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setPositionLocked(true, for: glassID)
  store.setKeepsOnTop(true, for: glassID)

  store.removeKeepOnTop(for: glassID)

  #expect(!store.keepsOnTop(glassID))
  #expect(store.isPositionLocked(for: glassID))
  #expect(defaults.object(forKey: "desktopGlass.keepOnTopIDs.v1") == nil)
}

@Test
func opacityPresetPersistsAcrossStoreInstances() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  #expect(store.opacityPreset(for: glassID) == .full)
  store.setOpacityPreset(.eighty, for: glassID)

  let restoredStore = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(restoredStore.opacityPreset(for: glassID) == .eighty)
  #expect(!restoredStore.isPositionLocked(for: glassID))
  #expect(!restoredStore.keepsOnTop(glassID))
}

@Test
func fullOpacityClearsStoredOverride() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  store.setOpacityPreset(.seventy, for: glassID)
  store.setOpacityPreset(.full, for: glassID)

  #expect(store.opacityPreset(for: glassID) == .full)
  #expect(defaults.object(forKey: "desktopGlass.opacityByID.v1") == nil)
}

@Test
func malformedOpacityValuesFallBackToFullOpacity() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  defaults.set(
    [
      glassID.rawValue.uuidString: 0.42,
      "not-a-uuid": 0.8,
    ],
    forKey: "desktopGlass.opacityByID.v1"
  )

  let store = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(store.opacityPreset(for: glassID) == .full)
}

@Test
func removingOpacityPresetKeepsOtherWindowPreferences() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setPositionLocked(true, for: glassID)
  store.setKeepsOnTop(true, for: glassID)
  store.setOpacityPreset(.ninety, for: glassID)

  store.removeOpacityPreset(for: glassID)

  #expect(store.opacityPreset(for: glassID) == .full)
  #expect(store.isPositionLocked(for: glassID))
  #expect(store.keepsOnTop(glassID))
  #expect(defaults.object(forKey: "desktopGlass.opacityByID.v1") == nil)
}
@Test
func compactFileTilesPersistAcrossStoreInstances() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  #expect(!store.usesCompactFileTiles(for: glassID))
  store.setUsesCompactFileTiles(true, for: glassID)

  let restoredStore = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(restoredStore.usesCompactFileTiles(for: glassID))
  #expect(!restoredStore.isPositionLocked(for: glassID))
  #expect(!restoredStore.keepsOnTop(glassID))
  #expect(restoredStore.opacityPreset(for: glassID) == .full)
}

@Test
func removingCompactFileTilesKeepsOtherWindowPreferences() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setPositionLocked(true, for: glassID)
  store.setKeepsOnTop(true, for: glassID)
  store.setOpacityPreset(.eighty, for: glassID)
  store.setUsesCompactFileTiles(true, for: glassID)

  store.removeCompactFileTiles(for: glassID)

  #expect(!store.usesCompactFileTiles(for: glassID))
  #expect(store.isPositionLocked(for: glassID))
  #expect(store.keepsOnTop(glassID))
  #expect(store.opacityPreset(for: glassID) == .eighty)
  #expect(defaults.object(forKey: "desktopGlass.compactFileTileIDs.v1") == nil)
}
