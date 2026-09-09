import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makePendingTopologyRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-pending-topology-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makePendingTopologyRecord() -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: GlassID(),
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString).partial",
        finalFilename: "payload.txt",
        expectedSize: 7,
        state: .recorded
    )
}

private func expectPendingUnsafeTopology(_ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("Expected unsafe pending-copy topology")
    } catch let error as PhysicalStateStoreError {
        #expect(error == .unsafeTopology)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test
func pendingMetadataLeafSymlinkIsNeverReadOrOverwritten() async throws {
    let fileManager = FileManager.default
    let root = try makePendingTopologyRoot()
    defer { try? fileManager.removeItem(at: root) }

    let external = root.appendingPathComponent("external.json", isDirectory: false)
    let externalData = Data("[]".utf8)
    try externalData.write(to: external)
    try fileManager.createSymbolicLink(
        at: root.appendingPathComponent(JSONPendingCopyStore.filename, isDirectory: false),
        withDestinationURL: external
    )

    let store = JSONPendingCopyStore(baseDirectory: root)
    await expectPendingUnsafeTopology {
        _ = try await store.records()
    }
    await expectPendingUnsafeTopology {
        try await store.upsert(makePendingTopologyRecord())
    }

    #expect(try Data(contentsOf: external) == externalData)
}

@Test
func productionFileOperationsSymlinkBlocksMetadataWrite() async throws {
    let fileManager = FileManager.default
    let root = try makePendingTopologyRoot()
    defer { try? fileManager.removeItem(at: root) }

    let externalDirectory = root.appendingPathComponent("external-file-operations", isDirectory: true)
    try fileManager.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(
        at: root.appendingPathComponent("FileOperations", isDirectory: true),
        withDestinationURL: externalDirectory
    )

    let store = JSONPendingCopyStore(
        applicationSupportRoot: root,
        relativeDirectory: "FileOperations"
    )
    await expectPendingUnsafeTopology {
        try await store.upsert(makePendingTopologyRecord())
    }

    #expect(!fileManager.fileExists(
        atPath: externalDirectory.appendingPathComponent(JSONPendingCopyStore.filename).path
    ))
}
