import Darwin
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassPersistenceAdapter

private func makeRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-config-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeConfiguration(
    title: String,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
) throws -> GlassConfiguration {
    try GlassConfiguration(
        title: title,
        source: FolderSource(
            bookmarkData: Data("test-bookmark".utf8),
            lastKnownPath: "/tmp/schneeglass-example-folder"
        ),
        placement: GlassPlacement(x: 40, y: 80),
        createdAt: createdAt
    )
}

private func setConfigurationFileMode(_ url: URL, mode: mode_t) throws {
    let result = url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
        guard let path else {
            return Int32(-1)
        }
        return chmod(path, mode)
    }
    guard result == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
}

@Test
func freshConfigurationStoreLoadsEmptyConfiguration() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = JSONConfigurationStore(baseDirectory: root)
    #expect(try await store.load().isEmpty)
    #expect(try await store.availableBackups().isEmpty)
}

@Test
func configurationRoundTripPreservesDomainValues() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let configuration = try makeConfiguration(
        title: "Projects",
        createdAt: Date(timeIntervalSinceReferenceDate: 812_345_678.123456)
    )
    let store = JSONConfigurationStore(baseDirectory: root)

    try await store.save([configuration])
    let loaded = try await store.load()

    #expect(loaded == [configuration])
}

@Test
func corruptCurrentConfigurationIsNeverSilentlyReplacedBySave() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let configurationDirectory = root.appendingPathComponent("Configuration", isDirectory: true)
    try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
    let currentURL = configurationDirectory.appendingPathComponent("config.json")
    let corruptData = Data("{not-json".utf8)
    try corruptData.write(to: currentURL)

    let store = JSONConfigurationStore(baseDirectory: root)

    do {
        try await store.save([try makeConfiguration(title: "Replacement")])
        Issue.record("Expected corrupt current configuration to block save")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .corruptCurrent)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(try Data(contentsOf: currentURL) == corruptData)
}

@Test
func unsupportedSchemaIsNotOverwrittenByOlderApplication() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let configurationDirectory = root.appendingPathComponent("Configuration", isDirectory: true)
    try FileManager.default.createDirectory(at: configurationDirectory, withIntermediateDirectories: true)
    let currentURL = configurationDirectory.appendingPathComponent("config.json")
    let futureData = Data("{\"glasses\":[],\"schemaVersion\":99}".utf8)
    try futureData.write(to: currentURL)

    let store = JSONConfigurationStore(baseDirectory: root)

    do {
        _ = try await store.load()
        Issue.record("Expected unsupported schema")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .unsupportedSchemaVersion(99))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    do {
        try await store.save([try makeConfiguration(title: "Older App")])
        Issue.record("Expected unsupported schema to block save")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .unsupportedSchemaVersion(99))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(try Data(contentsOf: currentURL) == futureData)
}

@Test
func configurationBackupsRotateToFiveGenerations() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = JSONConfigurationStore(baseDirectory: root)
    for index in 0..<8 {
        try await store.save([try makeConfiguration(title: "Version \(index)")])
    }

    let backups = try await store.availableBackups()
    #expect(backups.count == JSONConfigurationStore.maximumBackupCount)
}

@Test
func corruptBackupIsNotOfferedAsRecoveryCandidate() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = JSONConfigurationStore(baseDirectory: root)
    try await store.save([try makeConfiguration(title: "Version A")])
    try await store.save([try makeConfiguration(title: "Version B")])

    let backups = try await store.availableBackups()
    let descriptor = try #require(backups.first)
    let backupURL = root
        .appendingPathComponent("Configuration/Backups", isDirectory: true)
        .appendingPathComponent(descriptor.id)
    try Data("corrupt".utf8).write(to: backupURL)

    #expect(try await store.availableBackups().isEmpty)
}

@Test
func explicitRestorePreservesCorruptCurrentBeforeReplacingIt() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let versionA = try makeConfiguration(title: "Version A")
    let versionB = try makeConfiguration(title: "Version B")
    let store = JSONConfigurationStore(baseDirectory: root)

    try await store.save([versionA])
    try await store.save([versionB])
    let backup = try #require(try await store.availableBackups().first)

    let currentURL = root.appendingPathComponent("Configuration/config.json")
    let corruptData = Data("recover-me-if-needed".utf8)
    try corruptData.write(to: currentURL)

    do {
        _ = try await store.load()
        Issue.record("Expected corrupt current configuration")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .corruptCurrent)
    }

    let restored = try await store.restoreBackup(id: backup.id)
    #expect(restored == [versionA])
    #expect(try await store.load() == [versionA])

    let preservedDirectory = root.appendingPathComponent("Configuration/Preserved", isDirectory: true)
    let preservedFiles = try FileManager.default.contentsOfDirectory(
        at: preservedDirectory,
        includingPropertiesForKeys: nil
    )
    #expect(preservedFiles.count == 1)
    #expect(try Data(contentsOf: preservedFiles[0]) == corruptData)
}

@Test
func explicitRestoreDoesNotOverwriteUnsupportedFutureSchema() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let versionA = try makeConfiguration(title: "Version A")
    let versionB = try makeConfiguration(title: "Version B")
    let store = JSONConfigurationStore(baseDirectory: root)

    try await store.save([versionA])
    try await store.save([versionB])
    let backup = try #require(try await store.availableBackups().first)

    let currentURL = root.appendingPathComponent("Configuration/config.json", isDirectory: false)
    let futureData = Data("{\"glasses\":[],\"schemaVersion\":99}".utf8)
    try futureData.write(to: currentURL, options: .atomic)

    do {
        _ = try await store.restoreBackup(id: backup.id)
        Issue.record("Expected future schema to block explicit restore")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .unsupportedSchemaVersion(99))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(try Data(contentsOf: currentURL) == futureData)
    let preservedDirectory = root.appendingPathComponent("Configuration/Preserved", isDirectory: true)
    let preservedEntries = try FileManager.default.contentsOfDirectory(
        at: preservedDirectory,
        includingPropertiesForKeys: nil
    )
    #expect(preservedEntries.isEmpty)
}

@Test
func explicitRestoreDoesNotOverwriteUnreadableCurrent() async throws {
    let root = try makeRoot()
    let currentURL = root.appendingPathComponent("Configuration/config.json", isDirectory: false)
    defer {
        try? setConfigurationFileMode(currentURL, mode: 0o600)
        try? FileManager.default.removeItem(at: root)
    }

    let versionA = try makeConfiguration(title: "Version A")
    let versionB = try makeConfiguration(title: "Version B")
    let store = JSONConfigurationStore(baseDirectory: root)

    try await store.save([versionA])
    try await store.save([versionB])
    let backup = try #require(try await store.availableBackups().first)
    let currentData = try Data(contentsOf: currentURL)

    try setConfigurationFileMode(currentURL, mode: 0)

    do {
        _ = try await store.restoreBackup(id: backup.id)
        Issue.record("Expected unreadable current configuration to block explicit restore")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .corruptCurrent)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    try setConfigurationFileMode(currentURL, mode: 0o600)
    #expect(try Data(contentsOf: currentURL) == currentData)
    #expect(try await store.load() == [versionB])
}

@Test
func backupRestoreRejectsUnsafeIdentifier() async throws {
    let root = try makeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = JSONConfigurationStore(baseDirectory: root)

    do {
        _ = try await store.restoreBackup(id: "../config.json")
        Issue.record("Expected invalid backup identifier")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .invalidBackupIdentifier)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
