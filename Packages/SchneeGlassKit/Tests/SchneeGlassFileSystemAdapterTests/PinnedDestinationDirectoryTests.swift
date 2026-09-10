import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private struct DestinationTestRequest {
    let request: AuthorizedCopyBatchRequest
    let item: CopyItemPlan
}

private func makeDestinationTestRequest(
    destination: URL,
    source: URL,
    destinationFilename: String = "payload.txt"
) throws -> DestinationTestRequest {
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
    return DestinationTestRequest(
        request: AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access),
        item: item
    )
}

@Test
func pinnedCopyRejectsDestinationReplacementAfterPlanning() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-destination-replacement-\(UUID().uuidString)", isDirectory: true)
    let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    let movedDestination = root.appendingPathComponent("destination-original", isDirectory: true)
    let operations = root.appendingPathComponent("operations", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = sourceDirectory.appendingPathComponent("payload.txt")
    let payload = Data("safe-payload".utf8)
    try payload.write(to: source)

    let glassID = GlassID()
    let destinationValues = try destination.resourceValues(forKeys: [
        .volumeIdentifierKey,
        .fileResourceIdentifierKey,
    ])
    let access = FolderAccessHandle(
        glassID: glassID,
        url: destination,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: destinationValues.volumeIdentifier.map { String(describing: $0) },
            resourceIdentifier: destinationValues.fileResourceIdentifier.map { String(describing: $0) }
        )
    )
    let sourceLeases = SourceFileLeaseRegistry()
    let planner = NativeDropPlanningAdapter(sourceLeases: sourceLeases)
    let recoveryStore = JSONPendingCopyStore(baseDirectory: operations)
    let copier = PinnedSourceFileCopying(
        recoveryStore: recoveryStore,
        sourceLeases: sourceLeases
    )

    let drop = await planner.plan(sourceURLs: [source], destinationAccess: access)
    guard case let .copy(plan) = drop else {
        Issue.record("Expected authoritative copy plan, got \(drop)")
        return
    }
    #expect(await sourceLeases.activeLeaseCount() == 1)

    try FileManager.default.moveItem(at: destination, to: movedDestination)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let replacementMarker = destination.appendingPathComponent("replacement.txt")
    try Data("replacement-directory".utf8).write(to: replacementMarker)

    let result = await copier.copy(
        AuthorizedCopyBatchRequest(plan: plan, destinationAccess: access)
    )

    #expect(result.succeeded.isEmpty)
    #expect(result.failed?.reason == .destinationUnavailable)
    #expect(!FileManager.default.fileExists(
        atPath: destination.appendingPathComponent("payload.txt").path
    ))
    #expect(!FileManager.default.fileExists(
        atPath: movedDestination.appendingPathComponent("payload.txt").path
    ))
    #expect(try Data(contentsOf: replacementMarker) == Data("replacement-directory".utf8))
    #expect(await sourceLeases.activeLeaseCount() == 0)
    #expect(try await recoveryStore.records().isEmpty)
}

@Test
func pinnedCommitNeverOverwritesExistingFinalEntry() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-destination-collision-\(UUID().uuidString)", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("source.txt")
    try Data("source".utf8).write(to: source)
    let fixture = try makeDestinationTestRequest(destination: destination, source: source)
    let leases = DestinationDirectoryLeaseRegistry()
    try await leases.bind(fixture.request)

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
        await leases.release(batchID: fixture.request.plan.batchID)
        return
    }

    let final = destination.appendingPathComponent(fixture.item.destinationFilename)
    let existingPayload = Data("existing-final".utf8)
    try existingPayload.write(to: final)
    let committer = PinnedDestinationStagingCommitter(destinationLeases: leases)

    do {
        try await committer.commit(
            stagingURL: staging,
            finalURL: final,
            authorization: StagingCommitAuthorization(
                expectedSize: Int64(stagedPayload.count),
                expectedResourceIdentifier: token
            )
        )
        Issue.record("Expected exclusive final-name collision")
    } catch let error as StagingCommitError {
        #expect(error == .collision)
    }

    #expect(try Data(contentsOf: final) == existingPayload)
    #expect(try Data(contentsOf: staging) == stagedPayload)
    await leases.release(batchID: fixture.request.plan.batchID)
    #expect(await leases.activeLeaseCount() == 0)
}

@Test
func pinnedCommitTargetsOriginalPhysicalDirectoryAfterPathReplacement() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-destination-pinned-\(UUID().uuidString)", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    let movedDestination = root.appendingPathComponent("destination-moved", isDirectory: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let source = root.appendingPathComponent("source.txt")
    try Data("source".utf8).write(to: source)
    let fixture = try makeDestinationTestRequest(destination: destination, source: source)
    let leases = DestinationDirectoryLeaseRegistry()
    try await leases.bind(fixture.request)

    try FileManager.default.moveItem(at: destination, to: movedDestination)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let replacementMarker = destination.appendingPathComponent("replacement.txt")
    try Data("replacement".utf8).write(to: replacementMarker)

    let stagingFilename = DestinationDirectoryLeaseRegistry.stagingFilename(
        operationID: fixture.item.operationID
    )
    let physicalStaging = movedDestination.appendingPathComponent(stagingFilename)
    let stagedPayload = Data("pinned-payload".utf8)
    try stagedPayload.write(to: physicalStaging)
    guard let token = try PendingCopyFileIdentity.createToken(
        at: physicalStaging,
        fileManager: .default
    ) else {
        Issue.record("Expected staging ownership token")
        await leases.release(batchID: fixture.request.plan.batchID)
        return
    }

    let logicalStaging = destination.appendingPathComponent(stagingFilename)
    let logicalFinal = destination.appendingPathComponent(fixture.item.destinationFilename)
    let committer = PinnedDestinationStagingCommitter(destinationLeases: leases)
    try await committer.commit(
        stagingURL: logicalStaging,
        finalURL: logicalFinal,
        authorization: StagingCommitAuthorization(
            expectedSize: Int64(stagedPayload.count),
            expectedResourceIdentifier: token
        )
    )

    #expect(!FileManager.default.fileExists(atPath: logicalFinal.path))
    #expect(try Data(contentsOf: replacementMarker) == Data("replacement".utf8))
    let physicalFinal = movedDestination.appendingPathComponent(fixture.item.destinationFilename)
    #expect(try Data(contentsOf: physicalFinal) == stagedPayload)
    await leases.release(batchID: fixture.request.plan.batchID)
    #expect(await leases.activeLeaseCount() == 0)
}
