import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassPersistenceAdapter

private func makeConditionalSaveRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-config-cas-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func conditionalSaveConfiguration(
    title: String,
    marker: UInt8
) throws -> GlassConfiguration {
    try GlassConfiguration(
        title: title,
        source: FolderSource(
            bookmarkData: Data([marker]),
            lastKnownPath: "/tmp/\(title)"
        ),
        placement: GlassPlacement(x: Double(marker) * 10, y: Double(marker) * 20),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(marker))
    )
}

@Test
func conditionalSaveCommitsWhenCurrentSnapshotStillMatches() async throws {
    let root = try makeConditionalSaveRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let original = try conditionalSaveConfiguration(title: "Original", marker: 1)
    let replacement = try conditionalSaveConfiguration(title: "Replacement", marker: 2)
    let store = JSONConfigurationStore(baseDirectory: root)

    try await store.save([original])
    let expectedCurrent = try await store.load()

    let didSave = try await store.save(
        [replacement],
        ifCurrentMatches: expectedCurrent
    )

    #expect(didSave)
    #expect(try await store.load() == [replacement])
}

@Test
func conditionalSaveRejectsStaleSnapshotWithoutMutatingCurrentOrBackups() async throws {
    let root = try makeConditionalSaveRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let first = try conditionalSaveConfiguration(title: "First", marker: 1)
    let newer = try conditionalSaveConfiguration(title: "Newer", marker: 2)
    let staleReplacement = try conditionalSaveConfiguration(title: "Stale", marker: 3)
    let store = JSONConfigurationStore(baseDirectory: root)

    try await store.save([first])
    let staleSnapshot = try await store.load()
    try await store.save([newer])
    let backupsBeforeRejectedSave = try await store.availableBackups()

    let didSave = try await store.save(
        [staleReplacement],
        ifCurrentMatches: staleSnapshot
    )

    #expect(!didSave)
    #expect(try await store.load() == [newer])
    #expect(try await store.availableBackups() == backupsBeforeRejectedSave)
}
