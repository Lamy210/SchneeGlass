import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
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

private actor SnapshotRuntimeIdentityReader: RuntimeDirectoryIdentityReading {
    private let values: [POSIXDirectoryIdentity?]
    private var index = 0

    init(_ values: [POSIXDirectoryIdentity?]) {
        self.values = values
    }

    func identity(for url: URL) async -> POSIXDirectoryIdentity? {
        _ = url
        guard !values.isEmpty else {
            return nil
        }
        let current = min(index, values.count - 1)
        index += 1
        return values[current]
    }
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
        Issue.record("Expected root identity mismatch")
    } catch let error as FolderSnapshotReadError {
        #expect(error == .rootIdentityMismatch)
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

@Test
func snapshotRejectsRootThatDoesNotMatchAcquiredRuntimeIdentity() async throws {
    let root = try makeSnapshotIdentityRoot("acquired-posix-mismatch")
    defer { try? FileManager.default.removeItem(at: root) }

    let observed = POSIXDirectoryIdentity(device: 7, inode: 99)
    let reader = SnapshotRuntimeIdentityReader([observed])
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: root,
        fingerprint: nil,
        runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
            deviceIdentifier: 7,
            objectIdentifier: 41
        )
    )

    do {
        _ = try await NativeFolderSnapshotReader(
            fileManager: .default,
            runtimeIdentityReader: reader
        ).snapshot(for: access, generation: 3)
        Issue.record("Expected acquired runtime directory identity mismatch")
    } catch let error as FolderSnapshotReadError {
        #expect(error == .rootIdentityMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func snapshotAcceptsRootMatchingAcquiredRuntimeIdentity() async throws {
    let root = try makeSnapshotIdentityRoot("acquired-posix-match")
    defer { try? FileManager.default.removeItem(at: root) }

    let child = root.appendingPathComponent("visible.txt", isDirectory: false)
    try Data("visible".utf8).write(to: child)

    let observed = POSIXDirectoryIdentity(device: 7, inode: 41)
    let reader = SnapshotRuntimeIdentityReader([observed, observed])
    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: root,
        fingerprint: nil,
        runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
            deviceIdentifier: observed.device,
            objectIdentifier: observed.inode
        )
    )

    let snapshot = try await NativeFolderSnapshotReader(
        fileManager: .default,
        runtimeIdentityReader: reader
    ).snapshot(for: access, generation: 4)

    #expect(snapshot.items.map(\.displayName) == ["visible.txt"])
    #expect(snapshot.generation == 4)
}

@Test
func snapshotRejectsPOSIXRootReplacementAcrossEnumeration() async throws {
    let root = try makeSnapshotIdentityRoot("posix-replacement")
    defer { try? FileManager.default.removeItem(at: root) }

    let child = root.appendingPathComponent("visible.txt", isDirectory: false)
    try Data("visible".utf8).write(to: child)

    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: root,
        fingerprint: nil
    )
    let reader = SnapshotRuntimeIdentityReader([
        POSIXDirectoryIdentity(device: 7, inode: 41),
        POSIXDirectoryIdentity(device: 7, inode: 99),
    ])

    do {
        _ = try await NativeFolderSnapshotReader(
            fileManager: .default,
            runtimeIdentityReader: reader
        ).snapshot(for: access, generation: 5)
        Issue.record("Expected POSIX root identity mismatch")
    } catch let error as FolderSnapshotReadError {
        #expect(error == .rootIdentityMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func snapshotFailsClosedWhenObservedPOSIXIdentityDisappears() async throws {
    let root = try makeSnapshotIdentityRoot("posix-missing")
    defer { try? FileManager.default.removeItem(at: root) }

    let access = FolderAccessHandle(
        glassID: GlassID(),
        url: root,
        fingerprint: nil
    )
    let reader = SnapshotRuntimeIdentityReader([
        POSIXDirectoryIdentity(device: 7, inode: 41),
        nil,
    ])

    do {
        _ = try await NativeFolderSnapshotReader(
            fileManager: .default,
            runtimeIdentityReader: reader
        ).snapshot(for: access, generation: 6)
        Issue.record("Expected missing POSIX root identity to fail closed")
    } catch let error as FolderSnapshotReadError {
        #expect(error == .rootIdentityMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
