import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeCommitAuthorityRequest(
    destination: URL,
    source: URL,
    destinationFilename: String
) throws -> (request: AuthorizedCopyBatchRequest, item: CopyItemPlan) {
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
    return (
        AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access),
        item
    )
}

@Test
func pinnedCommitRejectsFinalFilenameOutsideBoundOperationAuthority() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-final-authority-\(UUID().uuidString)", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("source.txt")
    try Data("source".utf8).write(to: source)
    let fixture = try makeCommitAuthorityRequest(
        destination: destination,
        source: source,
        destinationFilename: "payload.txt"
    )
    let leases = DestinationDirectoryLeaseRegistry()
    try await leases.bind(fixture.request)
    defer {
        Task {
            await leases.release(batchID: fixture.request.plan.batchID)
        }
    }

    let stagingFilename = DestinationDirectoryLeaseRegistry.stagingFilename(
        operationID: fixture.item.operationID
    )
    let staging = destination.appendingPathComponent(stagingFilename)
    let stagedPayload = Data("staged-payload".utf8)
    try stagedPayload.write(to: staging)
    guard let token = try PendingCopyFileIdentity.createToken(
        at: staging,
        fileManager: .default
    ) else {
        Issue.record("Expected staging ownership token")
        return
    }

    let boundFinal = destination.appendingPathComponent(fixture.item.destinationFilename)
    let unboundFinal = destination.appendingPathComponent("other.txt")
    let committer = PinnedDestinationStagingCommitter(destinationLeases: leases)

    var observedError: StagingCommitError?
    do {
        try await committer.commit(
            stagingURL: staging,
            finalURL: unboundFinal,
            authorization: StagingCommitAuthorization(
                expectedSize: Int64(stagedPayload.count),
                expectedResourceIdentifier: token
            )
        )
    } catch let error as StagingCommitError {
        observedError = error
    }

    #expect(observedError == .commitFailed)
    #expect(FileManager.default.fileExists(atPath: staging.path))
    #expect(!FileManager.default.fileExists(atPath: boundFinal.path))
    #expect(!FileManager.default.fileExists(atPath: unboundFinal.path))
}
