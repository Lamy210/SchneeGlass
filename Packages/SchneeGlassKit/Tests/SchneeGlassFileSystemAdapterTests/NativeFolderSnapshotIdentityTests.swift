import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeSnapshotIdentityRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "SchneeGlassSnapshotIdentity-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return root
}

private func snapshotIdentityFingerprint(for url: URL) throws -> ResourceFingerprint {
    let values = try url.resourceValues(forKeys: [
        .volumeIdentifierKey,
        .fileResourceIdentifierKey,
    ])
    return ResourceFingerprint(
        volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) },
        resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
    )
}

@Test
func snapshotAcceptsRootMatchingSecurityScopedAccessFingerprint() async throws {
    let root = try makeSnapshotIdentityRoot("matching")
    defer { try? FileManager.default.removeItem(at: root) }

    let child = root.appendingPathComponent("visible.txt", isDirectory: false)
    try Data("visible".utf8).write(to: child)

    let fingerprint = try snapshotIdentityFingerprint(for: root)
    let expectedResourceIdentifier = try #require(fingerprint.resourceIdentifier)
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: root,
        fingerprint: fingerprint
    )

    let snapshot = try await NativeFolderSnapshotReader().snapshot(
        for: access,
        generation: 7
    )

    #expect(snapshot.folderIdentity.resourceIdentifier == expectedResourceIdentifier)
    #expect(snapshot.items.map(\.displayName) == ["visible.txt"])
    #expect(snapshot.generation == 7)
}

@Test
func snapshotRejectsRootThatDoesNotMatchSecurityScopedAccessFingerprint() async throws {
    let originalRoot = try makeSnapshotIdentityRoot("original")
    defer { try? FileManager.default.removeItem(at: originalRoot) }

    let replacementRoot = try makeSnapshotIdentityRoot("replacement")
    defer { try? FileManager.default.removeItem(at: replacementRoot) }

    let originalFingerprint = try snapshotIdentityFingerprint(for: originalRoot)
    let replacementFingerprint = try snapshotIdentityFingerprint(for: replacementRoot)
    let originalResourceIdentifier = try #require(originalFingerprint.resourceIdentifier)
    let replacementResourceIdentifier = try #require(replacementFingerprint.resourceIdentifier)
    #expect(originalResourceIdentifier != replacementResourceIdentifier)

    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: replacementRoot,
        fingerprint: originalFingerprint
    )

    do {
        _ = try await NativeFolderSnapshotReader().snapshot(
            for: access,
            generation: 1
        )
        Issue.record("Expected folderIdentityMismatch")
    } catch let error as NativeFolderSnapshotReaderError {
        #expect(error == .folderIdentityMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func snapshotKeepsLegacyFingerprintlessAccessCompatible() async throws {
    let root = try makeSnapshotIdentityRoot("legacy")
    defer { try? FileManager.default.removeItem(at: root) }

    let child = root.appendingPathComponent("legacy.txt", isDirectory: false)
    try Data("legacy".utf8).write(to: child)

    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: root,
        fingerprint: nil
    )

    let snapshot = try await NativeFolderSnapshotReader().snapshot(
        for: access,
        generation: 2
    )

    #expect(snapshot.items.map(\.displayName) == ["legacy.txt"])
    #expect(snapshot.generation == 2)
}
