import Foundation
import SchneeGlassDomain
import Testing
@testable import SchneeGlassPersistenceAdapter

private struct LegacyIdentityEnvelope: Encodable {
    let schemaVersion: Int
    let glasses: [LegacyIdentityConfiguration]
}

private struct LegacyIdentityConfiguration: Encodable {
    let id: GlassID
    let title: String
    let source: LegacyIdentityFolderSource
    let placement: GlassPlacement
    let showOnAllSpaces: Bool
    let createdAt: Date
}

private struct LegacyIdentityFolderSource: Encodable {
    let bookmarkData: Data
    let lastKnownPath: String
    let fingerprint: ResourceFingerprint
}

private func identityMigrationRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-folder-identity-migration-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func identityMigrationCurrentURL(root: URL) throws -> URL {
    let directory = root.appendingPathComponent("Configuration", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("config.json", isDirectory: false)
}

@Test
func legacyBootLocalFingerprintLoadsAndIsRemovedFromNextCurrentSave() async throws {
    let root = try identityMigrationRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let legacyFingerprint = ResourceFingerprint(
        volumeIdentifier: "boot-1-volume",
        resourceIdentifier: "boot-1-folder"
    )
    let legacyUUID = try #require(UUID(uuidString: "73D9E73A-4833-48CB-A97B-C9B44E87A7B9"))
    let legacy = LegacyIdentityEnvelope(
        schemaVersion: JSONConfigurationStore.schemaVersion,
        glasses: [
            LegacyIdentityConfiguration(
                id: GlassID(rawValue: legacyUUID),
                title: "Documents",
                source: LegacyIdentityFolderSource(
                    bookmarkData: Data("legacy-bookmark".utf8),
                    lastKnownPath: "/tmp/Documents",
                    fingerprint: legacyFingerprint
                ),
                placement: try GlassPlacement(x: 10, y: 20),
                showOnAllSpaces: false,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
        ]
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let currentURL = try identityMigrationCurrentURL(root: root)
    try encoder.encode(legacy).write(to: currentURL)

    let store = JSONConfigurationStore(baseDirectory: root)
    let loaded = try await store.load()
    let configuration = try #require(loaded.first)
    #expect(configuration.source.fingerprint == legacyFingerprint)
    #expect(configuration.source.persistentIdentity == nil)

    try await store.save(loaded)

    let migratedData = try Data(contentsOf: currentURL)
    let migratedText = try #require(String(data: migratedData, encoding: .utf8))
    #expect(!migratedText.contains("\"fingerprint\""))

    let reloaded = try await store.load()
    #expect(reloaded.count == 1)
    #expect(reloaded[0].source.fingerprint == nil)
    #expect(reloaded[0].source.bookmarkData == configuration.source.bookmarkData)
    #expect(reloaded[0].source.lastKnownPath == configuration.source.lastKnownPath)
}

@Test
func restartSafePersistentFolderIdentityRoundTripsWithoutRuntimeFingerprint() async throws {
    let root = try identityMigrationRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let persistentIdentity = PersistentFolderIdentity(
        volumeUUIDString: "58F0D944-7AE3-4B65-B918-29C31B7A06CB",
        documentIdentifier: 8123
    )
    let configuration = try GlassConfiguration(
        title: "Projects",
        source: FolderSource(
            bookmarkData: Data("bookmark".utf8),
            lastKnownPath: "/tmp/Projects",
            fingerprint: ResourceFingerprint(
                volumeIdentifier: "current-boot-volume",
                resourceIdentifier: "current-boot-folder"
            ),
            persistentIdentity: persistentIdentity
        ),
        placement: GlassPlacement(x: 40, y: 80),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    let store = JSONConfigurationStore(baseDirectory: root)
    try await store.save([configuration])

    let loaded = try await store.load()
    let restored = try #require(loaded.first)
    #expect(restored.source.persistentIdentity == persistentIdentity)
    #expect(restored.source.fingerprint == nil)

    let currentURL = root.appendingPathComponent("Configuration/config.json", isDirectory: false)
    let persistedText = try #require(String(data: Data(contentsOf: currentURL), encoding: .utf8))
    #expect(persistedText.contains("\"persistentIdentity\""))
    #expect(!persistedText.contains("\"fingerprint\""))
}
