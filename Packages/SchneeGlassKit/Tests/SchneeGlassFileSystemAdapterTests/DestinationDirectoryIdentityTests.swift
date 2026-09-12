import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import SchneeGlassPOSIXSupport
import Testing
@testable import SchneeGlassFileSystemAdapter

private func destinationIdentityRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "schneeglass-destination-identity-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func runtimeIdentity(for url: URL) throws -> RuntimeDirectoryIdentity {
    let identity = try #require(POSIXDirectoryIdentityReader.identity(at: url))
    return RuntimeDirectoryIdentity(
        deviceIdentifier: identity.device,
        objectIdentifier: identity.inode
    )
}

private func destinationPlan(
    root: URL,
    glassID: GlassID,
    resourceIdentifier: String? = nil
) throws -> CopyBatchPlan {
    let destination = DestinationDescriptor(
        glassID: glassID,
        folderIdentity: FolderIdentity(
            resourceIdentifier: resourceIdentifier,
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
    return try CopyBatchPlan(destination: destination, items: [item])
}

@Test
func destinationLeaseRejectsVolumeOnlyIdentityBeforeMutation() async throws {
    let root = try destinationIdentityRoot("volume-only")
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
    let plan = try destinationPlan(root: root, glassID: glassID)
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

@Test
func destinationLeaseAcceptsMatchingAcquiredRuntimeIdentityWithoutFoundationDirectoryID() async throws {
    let root = try destinationIdentityRoot("runtime-match")
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let access = FolderAccessHandle(
        glassID: glassID,
        url: root,
        fingerprint: nil,
        runtimeDirectoryIdentity: try runtimeIdentity(for: root)
    )
    let plan = try destinationPlan(root: root, glassID: glassID)
    let request = AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access)
    let leases = DestinationDirectoryLeaseRegistry()

    try await leases.bind(request)
    #expect(await leases.activeLeaseCount() == 1)

    await leases.release(batchID: plan.batchID)
    #expect(await leases.activeLeaseCount() == 0)
}

@Test
func destinationLeaseRejectsRuntimeIdentityThatNoLongerMatchesDestination() async throws {
    let root = try destinationIdentityRoot("runtime-mismatch")
    defer { try? FileManager.default.removeItem(at: root) }

    let values = try root.resourceValues(forKeys: [.fileResourceIdentifierKey])
    let resourceIdentifier = try #require(
        values.fileResourceIdentifier.map { String(describing: $0) }
    )
    let currentIdentity = try runtimeIdentity(for: root)
    let glassID = GlassID()
    let access = FolderAccessHandle(
        glassID: glassID,
        url: root,
        fingerprint: nil,
        runtimeDirectoryIdentity: RuntimeDirectoryIdentity(
            deviceIdentifier: currentIdentity.deviceIdentifier,
            objectIdentifier: currentIdentity.objectIdentifier &+ 1
        )
    )
    let plan = try destinationPlan(
        root: root,
        glassID: glassID,
        resourceIdentifier: resourceIdentifier
    )
    let request = AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access)
    let leases = DestinationDirectoryLeaseRegistry()

    do {
        try await leases.bind(request)
        Issue.record("Expected acquired runtime identity mismatch")
        await leases.release(batchID: plan.batchID)
    } catch let error as DestinationDirectoryLeaseError {
        #expect(error == .identityMismatch)
    }

    #expect(await leases.activeLeaseCount() == 0)
}
