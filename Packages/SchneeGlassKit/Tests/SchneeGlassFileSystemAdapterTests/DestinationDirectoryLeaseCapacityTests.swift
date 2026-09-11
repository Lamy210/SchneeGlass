import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeCapacityTestRequest(
    destination: URL,
    source: URL,
    destinationFilename: String
) throws -> AuthorizedCopyBatchRequest {
    let values = try destination.resourceValues(forKeys: [
        .volumeIdentifierKey,
        .fileResourceIdentifierKey,
        .volumeSupportsCaseSensitiveNamesKey,
    ])
    let volumeIdentifier = values.volumeIdentifier.map { String(describing: $0) }
    let resourceIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }
    let glassID = GlassID()
    let access = FolderAccessHandle(
        glassID: glassID,
        url: destination,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: volumeIdentifier,
            resourceIdentifier: resourceIdentifier
        )
    )
    let descriptor = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: resourceIdentifier,
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
func destinationLeaseCapacityRejectsAdditionalBatchUntilRelease() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-destination-capacity-\(UUID().uuidString)", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("source.txt")
    try Data("payload".utf8).write(to: source)

    let first = try makeCapacityTestRequest(
        destination: destination,
        source: source,
        destinationFilename: "first.txt"
    )
    let second = try makeCapacityTestRequest(
        destination: destination,
        source: source,
        destinationFilename: "second.txt"
    )
    let leases = DestinationDirectoryLeaseRegistry(maximumActiveLeases: 1)

    try await leases.bind(first)
    #expect(await leases.activeLeaseCount() == 1)

    do {
        try await leases.bind(second)
        Issue.record("Expected destination lease capacity rejection")
    } catch let error as DestinationDirectoryLeaseError {
        #expect(error == .destinationUnavailable)
    }
    #expect(await leases.activeLeaseCount() == 1)

    await leases.release(batchID: first.plan.batchID)
    #expect(await leases.activeLeaseCount() == 0)

    try await leases.bind(second)
    #expect(await leases.activeLeaseCount() == 1)

    await leases.release(batchID: second.plan.batchID)
    #expect(await leases.activeLeaseCount() == 0)
}
