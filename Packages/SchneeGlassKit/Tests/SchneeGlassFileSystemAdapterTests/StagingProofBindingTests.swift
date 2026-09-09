import Darwin
import Foundation
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func appOwnedStagingPreparationBindsProofToPinnedDescriptor() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-staging-proof-fd-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let staging = root.appendingPathComponent("staging.partial", isDirectory: false)
    let payload = Data("pinned-staging".utf8)
    try payload.write(to: staging)

    let descriptor = staging.withUnsafeFileSystemRepresentation { path in
        path.map { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) } ?? -1
    }
    #expect(descriptor >= 0)
    guard descriptor >= 0 else {
        return
    }
    defer { close(descriptor) }

    let prepared = PendingCopyFileIdentity.prepareAppOwnedStaging(
        onFileDescriptor: descriptor,
        pathURL: staging
    )
    let required = try #require(prepared)
    let proof = try #require(required.resourceIdentifier)
    let observed = try PendingCopyFileIdentity.token(at: staging, fileManager: .default)

    #expect(required.size == Int64(payload.count))
    #expect(observed == proof)
}

@Test
func appOwnedStagingPreparationNeverClaimsSamePathReplacement() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-staging-proof-replace-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let staging = root.appendingPathComponent("staging.partial", isDirectory: false)
    let original = Data("original-inode".utf8)
    let replacement = Data("replacement-inode".utf8)
    try original.write(to: staging)

    let descriptor = staging.withUnsafeFileSystemRepresentation { path in
        path.map { open($0, O_RDWR | O_CLOEXEC | O_NOFOLLOW) } ?? -1
    }
    #expect(descriptor >= 0)
    guard descriptor >= 0 else {
        return
    }
    defer { close(descriptor) }

    try FileManager.default.removeItem(at: staging)
    try replacement.write(to: staging)

    let prepared = PendingCopyFileIdentity.prepareAppOwnedStaging(
        onFileDescriptor: descriptor,
        pathURL: staging
    )
    let replacementProof = try PendingCopyFileIdentity.token(
        at: staging,
        fileManager: .default
    )

    #expect(prepared == nil)
    #expect(replacementProof == nil)
    #expect(try Data(contentsOf: staging) == replacement)
}
