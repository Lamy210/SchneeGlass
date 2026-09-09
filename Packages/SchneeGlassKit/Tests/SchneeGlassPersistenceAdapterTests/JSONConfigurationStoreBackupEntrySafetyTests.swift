import Darwin
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassPersistenceAdapter

private func makeBackupSafetyRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-backup-entry-safety-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeBackupSafetyConfiguration(title: String) throws -> GlassConfiguration {
    try GlassConfiguration(
        title: title,
        source: FolderSource(
            bookmarkData: Data("backup-safety-bookmark".utf8),
            lastKnownPath: "/tmp/schneeglass-backup-safety"
        ),
        placement: GlassPlacement(x: 40, y: 80),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func backupLikeName(timestamp: Int64) -> String {
    "backup-\(timestamp)-\(UUID().uuidString.lowercased()).json"
}

private func entryType(at url: URL) throws -> mode_t {
    var metadata = stat()
    let result = url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
        guard let path else {
            return Int32(-1)
        }
        return lstat(path, &metadata)
    }
    guard result == 0 else {
        throw CocoaError(.fileNoSuchFile)
    }
    return metadata.st_mode & S_IFMT
}

private func entryExists(at url: URL) -> Bool {
    var metadata = stat()
    return url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
        guard let path else {
            return false
        }
        return lstat(path, &metadata) == 0
    }
}

@Test
func backupRotationIgnoresBackupNamedDirectoryAndSymlink() async throws {
    let root = try makeBackupSafetyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = JSONConfigurationStore(baseDirectory: root)
    for index in 0..<7 {
        try await store.save([try makeBackupSafetyConfiguration(title: "Version \(index)")])
    }

    let backupDirectory = root.appendingPathComponent("Configuration/Backups", isDirectory: true)
    let directoryEntry = backupDirectory.appendingPathComponent(
        backupLikeName(timestamp: 1),
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directoryEntry, withIntermediateDirectories: false)
    let sentinel = directoryEntry.appendingPathComponent("must-survive.txt")
    try Data("sentinel".utf8).write(to: sentinel)

    let current = root.appendingPathComponent("Configuration/config.json", isDirectory: false)
    let symlinkEntry = backupDirectory.appendingPathComponent(
        backupLikeName(timestamp: 2),
        isDirectory: false
    )
    try FileManager.default.createSymbolicLink(at: symlinkEntry, withDestinationURL: current)

    // Trigger another backup and rotation. A filename-only filter would count the two hostile
    // directory entries as old backups and may recursively remove the directory.
    try await store.save([try makeBackupSafetyConfiguration(title: "After hostile entries")])

    let backups = try await store.availableBackups()
    #expect(backups.count == JSONConfigurationStore.maximumBackupCount)
    #expect(try entryType(at: directoryEntry) == S_IFDIR)
    #expect(try entryType(at: symlinkEntry) == S_IFLNK)
    #expect(try Data(contentsOf: sentinel) == Data("sentinel".utf8))
    #expect(!backups.contains { $0.id == directoryEntry.lastPathComponent })
    #expect(!backups.contains { $0.id == symlinkEntry.lastPathComponent })
}

@Test
func restoreRejectsBackupNamedSymlinkWithoutReadingTarget() async throws {
    let root = try makeBackupSafetyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let expected = try makeBackupSafetyConfiguration(title: "Current")
    let store = JSONConfigurationStore(baseDirectory: root)
    try await store.save([expected])

    let backupDirectory = root.appendingPathComponent("Configuration/Backups", isDirectory: true)
    let current = root.appendingPathComponent("Configuration/config.json", isDirectory: false)
    let backupName = backupLikeName(timestamp: 1)
    let symlinkEntry = backupDirectory.appendingPathComponent(backupName, isDirectory: false)
    try FileManager.default.createSymbolicLink(at: symlinkEntry, withDestinationURL: current)

    do {
        _ = try await store.restoreBackup(id: backupName)
        Issue.record("Expected non-regular backup entry to be rejected")
    } catch let error as ConfigurationPersistenceError {
        #expect(error == .backupNotFound)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(try await store.load() == [expected])
    #expect(try entryType(at: symlinkEntry) == S_IFLNK)
}

@Test
func backupRotatorCannotRecursivelyDeleteDirectoryEvenIfCalledDirectly() throws {
    let root = try makeBackupSafetyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let directory = root.appendingPathComponent(backupLikeName(timestamp: 1), isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let sentinel = directory.appendingPathComponent("must-survive.txt", isDirectory: false)
    try Data("sentinel".utf8).write(to: sentinel)

    let candidates = [directory]
    do {
        try ConfigurationBackupRotator.removeBackups(candidates[...])
        Issue.record("Expected unlink to reject a directory")
    } catch let error as ConfigurationBackupRotationError {
        switch error {
        case .unlinkFailed:
            break
        case .invalidPath:
            Issue.record("Unexpected invalid path")
        }
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(try entryType(at: directory) == S_IFDIR)
    #expect(try Data(contentsOf: sentinel) == Data("sentinel".utf8))
}

@Test
func backupRotatorUnlinksSymlinkEntryWithoutFollowingTarget() throws {
    let root = try makeBackupSafetyRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let target = root.appendingPathComponent("target.json", isDirectory: false)
    let payload = Data("target-must-survive".utf8)
    try payload.write(to: target)

    let symlink = root.appendingPathComponent(backupLikeName(timestamp: 1), isDirectory: false)
    try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
    #expect(try entryType(at: symlink) == S_IFLNK)

    let candidates = [symlink]
    try ConfigurationBackupRotator.removeBackups(candidates[...])

    #expect(!entryExists(at: symlink))
    #expect(try Data(contentsOf: target) == payload)
}
