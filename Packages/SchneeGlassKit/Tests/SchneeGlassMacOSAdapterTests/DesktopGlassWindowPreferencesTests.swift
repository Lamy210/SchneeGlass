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
func malformedCompactFileTileIdentifiersAreIgnored() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  defaults.set(
    ["not-a-uuid"],
    forKey: "desktopGlass.compactFileTileIDs.v1"
  )

  let store = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(!store.usesCompactFileTiles(for: GlassID()))
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

@Test
func fileSortPreferencePersistsAcrossStoreInstances() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  #expect(store.fileSortPreference(for: glassID) == .nameAscending)
  store.setFileSortPreference(.modifiedNewest, for: glassID)

  let restoredStore = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(restoredStore.fileSortPreference(for: glassID) == .modifiedNewest)
  #expect(!restoredStore.usesCompactFileTiles(for: glassID))
  #expect(restoredStore.opacityPreset(for: glassID) == .full)
}

@Test
func defaultFileSortClearsStoredOverride() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setFileSortPreference(.sizeLargest, for: glassID)
  store.setFileSortPreference(.nameAscending, for: glassID)

  #expect(store.fileSortPreference(for: glassID) == .nameAscending)
  #expect(defaults.object(forKey: "desktopGlass.fileSortByID.v1") == nil)
}

@Test
func malformedFileSortValuesFallBackToNameAscending() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  defaults.set(
    [
      glassID.rawValue.uuidString: "unsupported-sort",
      "not-a-uuid": DesktopGlassFileSortPreference.sizeLargest.rawValue,
    ],
    forKey: "desktopGlass.fileSortByID.v1"
  )

  let store = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(store.fileSortPreference(for: glassID) == .nameAscending)
}

@Test
func removingFileSortKeepsOtherWindowPreferences() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setPositionLocked(true, for: glassID)
  store.setOpacityPreset(.eighty, for: glassID)
  store.setUsesCompactFileTiles(true, for: glassID)
  store.setFileSortPreference(.modifiedNewest, for: glassID)

  store.removeFileSortPreference(for: glassID)

  #expect(store.fileSortPreference(for: glassID) == .nameAscending)
  #expect(store.isPositionLocked(for: glassID))
  #expect(store.opacityPreset(for: glassID) == .eighty)
  #expect(store.usesCompactFileTiles(for: glassID))
  #expect(defaults.object(forKey: "desktopGlass.fileSortByID.v1") == nil)
}

@Test
func foldersFirstPersistsAcrossStoreInstances() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  #expect(!store.putsFoldersFirst(for: glassID))
  store.setFoldersFirst(true, for: glassID)

  let restoredStore = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(restoredStore.putsFoldersFirst(for: glassID))
  #expect(restoredStore.fileSortPreference(for: glassID) == .nameAscending)
}

@Test
func malformedFoldersFirstIdentifiersAreIgnored() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  defaults.set(
    ["not-a-uuid"],
    forKey: "desktopGlass.foldersFirstIDs.v1"
  )

  let store = DesktopGlassWindowPreferences(defaults: defaults)
  #expect(!store.putsFoldersFirst(for: GlassID()))
}

@Test
func removingFoldersFirstKeepsSortAndOtherWindowPreferences() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setPositionLocked(true, for: glassID)
  store.setOpacityPreset(.eighty, for: glassID)
  store.setFileSortPreference(.modifiedNewest, for: glassID)
  store.setFoldersFirst(true, for: glassID)

  store.removeFoldersFirst(for: glassID)

  #expect(!store.putsFoldersFirst(for: glassID))
  #expect(store.isPositionLocked(for: glassID))
  #expect(store.opacityPreset(for: glassID) == .eighty)
  #expect(store.fileSortPreference(for: glassID) == .modifiedNewest)
  #expect(defaults.object(forKey: "desktopGlass.foldersFirstIDs.v1") == nil)
}

@Test
func retainingPreferencesRemovesStateForGlassesNoLongerInConfiguration() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let retainedID = GlassID()
  let removedID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)

  for glassID in [retainedID, removedID] {
    store.setPositionLocked(true, for: glassID)
    store.setKeepsOnTop(true, for: glassID)
    store.setOpacityPreset(.eighty, for: glassID)
    store.setUsesCompactFileTiles(true, for: glassID)
    store.setFileSortPreference(.sizeLargest, for: glassID)
    store.setFoldersFirst(true, for: glassID)
  }

  store.retainPreferences(onlyFor: [retainedID])

  #expect(store.isPositionLocked(for: retainedID))
  #expect(store.keepsOnTop(retainedID))
  #expect(store.opacityPreset(for: retainedID) == .eighty)
  #expect(store.usesCompactFileTiles(for: retainedID))
  #expect(store.fileSortPreference(for: retainedID) == .sizeLargest)
  #expect(store.putsFoldersFirst(for: retainedID))

  #expect(!store.isPositionLocked(for: removedID))
  #expect(!store.keepsOnTop(removedID))
  #expect(store.opacityPreset(for: removedID) == .full)
  #expect(!store.usesCompactFileTiles(for: removedID))
  #expect(store.fileSortPreference(for: removedID) == .nameAscending)
  #expect(!store.putsFoldersFirst(for: removedID))
}

@Test
func retainingNoGlassPreferencesClearsAllWindowPreferenceStorage() throws {
  let suiteName = "DesktopGlassWindowPreferencesTests-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suiteName))
  defer { defaults.removePersistentDomain(forName: suiteName) }

  let glassID = GlassID()
  let store = DesktopGlassWindowPreferences(defaults: defaults)
  store.setPositionLocked(true, for: glassID)
  store.setKeepsOnTop(true, for: glassID)
  store.setOpacityPreset(.seventy, for: glassID)
  store.setUsesCompactFileTiles(true, for: glassID)
  store.setFileSortPreference(.modifiedNewest, for: glassID)
  store.setFoldersFirst(true, for: glassID)

  store.retainPreferences(onlyFor: [])

  #expect(defaults.object(forKey: "desktopGlass.lockedPositionIDs.v1") == nil)
  #expect(defaults.object(forKey: "desktopGlass.keepOnTopIDs.v1") == nil)
  #expect(defaults.object(forKey: "desktopGlass.opacityByID.v1") == nil)
  #expect(defaults.object(forKey: "desktopGlass.compactFileTileIDs.v1") == nil)
  #expect(defaults.object(forKey: "desktopGlass.fileSortByID.v1") == nil)
  #expect(defaults.object(forKey: "desktopGlass.foldersFirstIDs.v1") == nil)
}
