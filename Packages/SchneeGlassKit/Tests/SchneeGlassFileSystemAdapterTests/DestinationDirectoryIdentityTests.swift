import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

@Test
func destinationLeaseRejectsVolumeOnlyIdentityBeforeMutation() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "schneeglass-destination-identity-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let values = try root.resourceValues(forKeys: [.volumeIdentifierKey])
    let glassID = GlassID()
    let access = FolderAccessHandle(
        glassID: glassID,
        url: root,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) },
            resourceIdentifier: nil
        )
    )
    let destination = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: nil,
            standardizedURL: root
        ),
        url: root,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: nil
        )
    )
    let source = root
        .deletingLastPathComponent()
        .appendingPathComponent("external-\(UUID().uuidString).txt")
    let item = CopyItemPlan(
        sourceURL: source,
        originalFilename: source.lastPathComponent,
        destinationFilename: source.lastPathComponent
    )
    let plan = try CopyBatchPlan(destination: destination, items: [item])
    let request = AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access)
    let leases = DestinationDirectoryLeaseRegistry()

    do {
        try await leases.bind(request)
        Issue.record("Expected destination identity mismatch")
        await leases.release(batchID: plan.batchID)
    } catch let error as DestinationDirectoryLeaseError {
        #expect(error == .identityMismatch)
    }

    #expect(await leases.activeLeaseCount() == 0)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
}
