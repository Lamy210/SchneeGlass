import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makePreflightSafetyRequest(
    destination: URL,
    items: [CopyItemPlan]
) throws -> AuthorizedCopyBatchRequest {
    let glassID = GlassID()
    let destinationURL = destination.standardizedFileURL
    let descriptor = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: nil,
            standardizedURL: destinationURL
        ),
        url: destinationURL,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true
        )
    )
    return AuthorizedCopyBatchRequest(
        plan: try CopyBatchPlan(destination: descriptor, items: items),
        destinationAccess: FolderAccessHandle(
            glassID: glassID,
            url: destinationURL
        )
    )
}

@Test
func duplicateFinalFilenameIsRejectedBeforeAnyFilesystemMutation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-duplicate-preflight-\(UUID().uuidString)", isDirectory: true)
    let sourceA = root.appendingPathComponent("source-a", isDirectory: true)
    let sourceB = root.appendingPathComponent("source-b", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    let recoveryDirectory = root.appendingPathComponent("recovery", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: sourceB, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let firstSource = sourceA.appendingPathComponent("duplicate.txt")
    let secondSource = sourceB.appendingPathComponent("duplicate.txt")
    let firstPayload = Data("first".utf8)
    let secondPayload = Data("second".utf8)
    try firstPayload.write(to: firstSource)
    try secondPayload.write(to: secondSource)

    let first = CopyItemPlan(
        sourceURL: firstSource,
        originalFilename: "duplicate.txt",
        destinationFilename: "duplicate.txt",
        expectedSize: Int64(firstPayload.count)
    )
    let second = CopyItemPlan(
        sourceURL: secondSource,
        originalFilename: "duplicate.txt",
        destinationFilename: "duplicate.txt",
        expectedSize: Int64(secondPayload.count)
    )
    let request = try makePreflightSafetyRequest(
        destination: destination,
        items: [first, second]
    )
    let recovery = JSONPendingCopyStore(baseDirectory: recoveryDirectory)
    let engine = SafeFileCopyEngine(recoveryStore: recovery)

    let result = await engine.copy(request)
    let destinationEntries = try FileManager.default.contentsOfDirectory(atPath: destination.path)
    let firstAfter = try Data(contentsOf: firstSource)
    let secondAfter = try Data(contentsOf: secondSource)
    let pending = try await recovery.records()

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.operationID == second.operationID)
    #expect(result.failed?.reason == .collision)
    #expect(destinationEntries.isEmpty)
    #expect(firstAfter == firstPayload)
    #expect(secondAfter == secondPayload)
    #expect(pending.isEmpty)
}

@Test
func traversalDestinationFilenameIsRejectedBeforeMutation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-traversal-preflight-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    let recoveryDirectory = root.appendingPathComponent("recovery", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = sourceDirectory.appendingPathComponent("safe.txt")
    let payload = Data("safe".utf8)
    try payload.write(to: source)

    let item = CopyItemPlan(
        sourceURL: source,
        originalFilename: "safe.txt",
        destinationFilename: "../escaped.txt",
        expectedSize: Int64(payload.count)
    )
    let request = try makePreflightSafetyRequest(
        destination: destination,
        items: [item]
    )
    let recovery = JSONPendingCopyStore(baseDirectory: recoveryDirectory)
    let engine = SafeFileCopyEngine(recoveryStore: recovery)

    let result = await engine.copy(request)
    let escaped = root.appendingPathComponent("escaped.txt")
    let pending = try await recovery.records()

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.reason == .unsupportedItem)
    #expect(!FileManager.default.fileExists(atPath: escaped.path))
    #expect(try Data(contentsOf: source) == payload)
    #expect(pending.isEmpty)
}
