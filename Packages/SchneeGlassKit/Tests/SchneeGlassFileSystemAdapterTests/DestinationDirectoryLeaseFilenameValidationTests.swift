import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeDestinationLeaseValidationRequest(
    destination: URL,
    destinationFilename: String
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
    let item = CopyItemPlan(
        sourceURL: URL(fileURLWithPath: "/tmp/schneeglass-unused-source"),
        originalFilename: "payload.txt",
        destinationFilename: destinationFilename,
        expectedSize: 1
    )
    return AuthorizedCopyBatchRequest(
        plan: try CopyBatchPlan(destination: descriptor, items: [item]),
        destinationAccess: FolderAccessHandle(glassID: glassID, url: destinationURL)
    )
}

@Test(arguments: [".", ".."])
func destinationLeaseRejectsReservedDotFilename(_ destinationFilename: String) async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-destination-name-validation-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let request = try makeDestinationLeaseValidationRequest(
        destination: root,
        destinationFilename: destinationFilename
    )
    let leases = DestinationDirectoryLeaseRegistry()

    do {
        try await leases.bind(request)
        await leases.release(batchID: request.plan.batchID)
        Issue.record("Expected reserved dot destination filename to be rejected before lease binding")
    } catch let error as DestinationDirectoryLeaseError {
        #expect(error == .destinationUnavailable)
    }

    #expect(await leases.activeLeaseCount() == 0)
}
