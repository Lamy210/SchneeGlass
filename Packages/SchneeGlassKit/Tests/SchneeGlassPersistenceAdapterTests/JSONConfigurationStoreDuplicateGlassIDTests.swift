import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

@testable import SchneeGlassPersistenceAdapter

private struct DuplicateGlassIDEnvelope: Encodable {
  let schemaVersion: Int
  let glasses: [GlassConfiguration]
}

private func makeDuplicateGlassIDRoot() throws -> URL {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "schneeglass-duplicate-glass-id-\(UUID().uuidString)",
      isDirectory: true
    )
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  return root
}

private func duplicateGlassIDConfigurations() throws -> [GlassConfiguration] {
  let id = GlassID()
  let first = try GlassConfiguration(
    id: id,
    title: "First",
    source: FolderSource(
      bookmarkData: Data([1]),
      lastKnownPath: "/tmp/duplicate-glass-id-first"
    ),
    placement: GlassPlacement(x: 100, y: 120),
    createdAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
  let second = try GlassConfiguration(
    id: id,
    title: "Second",
    source: FolderSource(
      bookmarkData: Data([2]),
      lastKnownPath: "/tmp/duplicate-glass-id-second"
    ),
    placement: GlassPlacement(x: 220, y: 240),
    createdAt: Date(timeIntervalSince1970: 1_700_000_001)
  )
  return [first, second]
}

private func duplicateGlassIDEnvelopeData(
  configurations: [GlassConfiguration]
) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(
    DuplicateGlassIDEnvelope(
      schemaVersion: JSONConfigurationStore.schemaVersion,
      glasses: configurations
    )
  )
}

@Test
func duplicateGlassIDsInCurrentConfigurationFailClosedAsCorrupt() async throws {
  let root = try makeDuplicateGlassIDRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let configurationDirectory = root.appendingPathComponent(
    "Configuration",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: configurationDirectory,
    withIntermediateDirectories: true
  )

  let configurations = try duplicateGlassIDConfigurations()
  try duplicateGlassIDEnvelopeData(configurations: configurations).write(
    to: configurationDirectory.appendingPathComponent("config.json")
  )

  let store = JSONConfigurationStore(baseDirectory: root)
  do {
    _ = try await store.load()
    Issue.record("Expected duplicate Glass IDs to be rejected")
  } catch let error as ConfigurationPersistenceError {
    #expect(error == .corruptCurrent)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test
func duplicateGlassIDsInBackupAreNotOfferedOrRestored() async throws {
  let root = try makeDuplicateGlassIDRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let backupDirectory = root.appendingPathComponent(
    "Configuration/Backups",
    isDirectory: true
  )
  try FileManager.default.createDirectory(
    at: backupDirectory,
    withIntermediateDirectories: true
  )

  let backupName = "backup-1700000000000-\(UUID().uuidString.lowercased()).json"
  let configurations = try duplicateGlassIDConfigurations()
  try duplicateGlassIDEnvelopeData(configurations: configurations).write(
    to: backupDirectory.appendingPathComponent(backupName)
  )

  let store = JSONConfigurationStore(baseDirectory: root)
  #expect(try await store.availableBackups().isEmpty)

  do {
    _ = try await store.restoreBackup(id: backupName)
    Issue.record("Expected duplicate-ID backup to be rejected")
  } catch let error as ConfigurationPersistenceError {
    #expect(error == .corruptBackup)
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

@Test
func duplicateGlassIDsCannotReplaceValidCurrentConfiguration() async throws {
  let root = try makeDuplicateGlassIDRoot()
  defer { try? FileManager.default.removeItem(at: root) }

  let configurations = try duplicateGlassIDConfigurations()
  let valid = configurations[0]
  let store = JSONConfigurationStore(baseDirectory: root)
  try await store.save([valid])

  do {
    try await store.save(configurations)
    Issue.record("Expected duplicate Glass IDs to be rejected before persistence")
  } catch {
    // Higher-level callers map this internal validation error to their existing save-failure
    // contracts. The invariant here is that invalid state never replaces valid current state.
  }

  #expect(try await store.load() == [valid])
}
