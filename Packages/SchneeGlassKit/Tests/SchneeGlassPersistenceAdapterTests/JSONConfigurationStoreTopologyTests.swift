import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassPersistenceAdapter

private func makeTopologyRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-config-topology-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeTopologyConfiguration(_ title: String) throws -> GlassConfiguration {
    try GlassConfiguration(
        title: title,
        source: FolderSource(
            bookmarkData: Data("topology-test-bookmark".utf8),
            lastKnownPath: "/tmp/schneeglass-topology-example"
        ),
        placement: GlassPlacement(x: 80, y: 120),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func expectUnsafeTopology(_ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected unsafe storage topology")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .unsafeStorageTopology)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func configurationLeafSymlinkIsNeverReadOrOverwritten() async throws {
    let fileManager = FileManager.default
    let root = try makeTopologyRoot()
    defer { try? fileManager.removeItem(at: root) }

    let configurationDirectory = root.appendingPathComponent("Configuration", isDirectory: true)
    try fileManager.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
    let external = root.appendingPathComponent("external.json", isDirectory: false)
    let externalData = Data("external-user-data".utf8)
    try externalData.write(to: external)
    try fileManager.createSymbolicLink(
        at: configurationDirectory.appendingPathComponent("config.json"),
        withDestinationURL: external
    )

    let store = JSONConfigurationStore(baseDirectory: root)
    await expectUnsafeTopology {
        _ = try await store.load()
    }
    await expectUnsafeTopology {
        try await store.save([try makeTopologyConfiguration("Replacement")])
    }

    #expect(try Data(contentsOf: external) == externalData)
}

@Test
func configurationDirectorySymlinkBlocksSaveWithoutWritingItsTarget() async throws {
    let fileManager = FileManager.default
    let root = try makeTopologyRoot()
    defer { try? fileManager.removeItem(at: root) }

    let externalDirectory = root.appendingPathComponent("external-configuration", isDirectory: true)
    try fileManager.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(
        at: root.appendingPathComponent("Configuration", isDirectory: true),
        withDestinationURL: externalDirectory
    )

    let store = JSONConfigurationStore(baseDirectory: root)
    await expectUnsafeTopology {
        try await store.save([try makeTopologyConfiguration("Projects")])
    }

    #expect(!fileManager.fileExists(
        atPath: externalDirectory.appendingPathComponent("config.json").path
    ))
}

@Test
func backupDirectorySymlinkBlocksSaveBeforeCurrentConfigurationChanges() async throws {
    let fileManager = FileManager.default
    let root = try makeTopologyRoot()
    defer { try? fileManager.removeItem(at: root) }

    let store = JSONConfigurationStore(baseDirectory: root)
    try await store.save([try makeTopologyConfiguration("Version A")])

    let configurationDirectory = root.appendingPathComponent("Configuration", isDirectory: true)
    let currentURL = configurationDirectory.appendingPathComponent("config.json", isDirectory: false)
    let before = try Data(contentsOf: currentURL)

    let externalBackups = root.appendingPathComponent("external-backups", isDirectory: true)
    try fileManager.createDirectory(at: externalBackups, withIntermediateDirectories: true)
    let backupsPath = configurationDirectory.appendingPathComponent("Backups", isDirectory: true)
    if fileManager.fileExists(atPath: backupsPath.path) {
        try fileManager.removeItem(at: backupsPath)
    }
    try fileManager.createSymbolicLink(
        at: backupsPath,
        withDestinationURL: externalBackups
    )

    await expectUnsafeTopology {
        try await store.save([try makeTopologyConfiguration("Version B")])
    }

    #expect(try Data(contentsOf: currentURL) == before)
    #expect(try fileManager.contentsOfDirectory(atPath: externalBackups.path).isEmpty)
}

@Test
func preservedDirectorySymlinkBlocksExplicitRestoreBeforeCurrentMutation() async throws {
    let fileManager = FileManager.default
    let root = try makeTopologyRoot()
    defer { try? fileManager.removeItem(at: root) }

    let store = JSONConfigurationStore(baseDirectory: root)
    try await store.save([try makeTopologyConfiguration("Version A")])
    try await store.save([try makeTopologyConfiguration("Version B")])
    let backup = try #require(try await store.availableBackups().first)

    let configurationDirectory = root.appendingPathComponent("Configuration", isDirectory: true)
    let currentURL = configurationDirectory.appendingPathComponent("config.json", isDirectory: false)
    let corruptCurrent = Data("{corrupt-current".utf8)
    try corruptCurrent.write(to: currentURL, options: .atomic)

    let externalPreserved = root.appendingPathComponent("external-preserved", isDirectory: true)
    try fileManager.createDirectory(at: externalPreserved, withIntermediateDirectories: true)
    let preservedPath = configurationDirectory.appendingPathComponent("Preserved", isDirectory: true)
    if fileManager.fileExists(atPath: preservedPath.path) {
        try fileManager.removeItem(at: preservedPath)
    }
    try fileManager.createSymbolicLink(at: preservedPath, withDestinationURL: externalPreserved)

    await expectUnsafeTopology {
        _ = try await store.restoreBackup(id: backup.id)
    }

    #expect(try Data(contentsOf: currentURL) == corruptCurrent)
    #expect(try fileManager.contentsOfDirectory(atPath: externalPreserved.path).isEmpty)
}
