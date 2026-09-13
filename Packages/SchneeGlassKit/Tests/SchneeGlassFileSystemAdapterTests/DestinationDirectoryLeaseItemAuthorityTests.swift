import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeItemAuthorityRequest(
    destination: URL,
    source: URL,
    destinationFilename: String
) throws -> AuthorizedCopyBatchRequest {
    let values = try destination.resourceValues(forKeys: [
        .volumeSupportsCaseSensitiveNamesKey,
    ])
    let glassID = GlassID()
    let access = FolderAccessHandle(
        glassID: glassID,
        url: destination,
        runtimeDirectoryIdentity: try testRuntimeDirectoryIdentity(for: destination)
    )
    let descriptor = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: nil,
            standardizedURL: destination
        ),
        url: destination,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: values.volumeSupportsCaseSensitiveNames
        )
    )
    let item = CopyItemPlan(
        sourceURL: source,
        originalFilename: source.lastPathComponent,
        destinationFilename: destinationFilename,
        expectedSize: nil
    )
    let plan = try CopyBatchPlan(destination: descriptor, items: [item])
    return AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access)
}

@Test
func destinationExistenceLookupUsesTheBoundOperationDirectory() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-item-authority-\(UUID().uuidString)", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    let originalDestination = root.appendingPathComponent("destination-original", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("source.txt")
    try Data("payload".utf8).write(to: source)

    let first = try makeItemAuthorityRequest(
        destination: destination,
        source: source,
        destinationFilename: "payload.txt"
    )
    let leases = DestinationDirectoryLeaseRegistry()
    try await leases.bind(first)

    try FileManager.default.moveItem(at: destination, to: originalDestination)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let replacementFinal = destination.appendingPathComponent("payload.txt")
    try Data("replacement".utf8).write(to: replacementFinal)

    let second = try makeItemAuthorityRequest(
        destination: destination,
        source: source,
        destinationFilename: "payload.txt"
    )
    try await leases.bind(second)

    let logicalFinal = destination.appendingPathComponent("payload.txt")
    let firstOperationID = first.plan.items[0].operationID
    let secondOperationID = second.plan.items[0].operationID

    #expect(await leases.itemExists(at: logicalFinal, operationID: firstOperationID) == false)
    #expect(await leases.itemExists(at: logicalFinal, operationID: secondOperationID) == true)

    await leases.release(batchID: first.plan.batchID)
    await leases.release(batchID: second.plan.batchID)
    #expect(await leases.activeLeaseCount() == 0)
}
