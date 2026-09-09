import Foundation
import SchneeGlassDomain
import Testing
@testable import SchneeGlassPersistenceAdapter

private func makeCommitSemanticsRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "schneeglass-config-commit-tests-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeCommitSemanticsConfiguration(title: String) throws -> GlassConfiguration {
    try GlassConfiguration(
        title: title,
        source: FolderSource(
            bookmarkData: Data("test-bookmark".utf8),
            lastKnownPath: "/tmp/schneeglass-commit-semantics"
        ),
        placement: GlassPlacement(x: 40, y: 80),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func backupFilename(milliseconds: Int64) -> String {
    "backup-\(milliseconds)-\(UUID().uuidString.lowercased()).json"
}

@Test
func failedBackupRotationDoesNotCommitNewCurrentConfiguration() async throws {
    let root = try makeCommitSemanticsRoot()
    var blockedBackupURL: URL?
    defer {
        if let blockedBackupURL {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: blockedBackupURL.path
            )
        }
        try? FileManager.default.removeItem(at: root)
    }

    let original = try makeCommitSemanticsConfiguration(title: "Original")
    let replacement = try makeCommitSemanticsConfiguration(title: "Replacement")
    let store = JSONConfigurationStore(baseDirectory: root)
    try await store.save([original])

    let backupDirectory = root.appendingPathComponent("Configuration/Backups", isDirectory: true)

    let blocked = backupDirectory.appendingPathComponent(
        backupFilename(milliseconds: 1),
        isDirectory: true
    )
    blockedBackupURL = blocked
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
    try Data("owned-by-test".utf8).write(to: blocked.appendingPathComponent("child"))
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o500],
        ofItemAtPath: blocked.path
    )

    for milliseconds in 2...5 {
        let backupURL = backupDirectory.appendingPathComponent(
            backupFilename(milliseconds: Int64(milliseconds)),
            isDirectory: false
        )
        try Data("rotation-fixture".utf8).write(to: backupURL)
    }

    var saveFailed = false
    do {
        try await store.save([replacement])
    } catch {
        saveFailed = true
    }

    #expect(saveFailed)
    #expect(try await store.load() == [original])
}
