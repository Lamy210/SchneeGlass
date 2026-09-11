import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum PendingPlanAuthorityTestError: Error, Sendable {
    case unexpectedCall
}

private actor PendingPlanAuthorityAccessController: FolderAccessControlling {
    private var releasedHandleIDs: [UUID] = []

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        throw PendingPlanAuthorityTestError.unexpectedCall
    }

    func release(handleID: UUID) async {
        releasedHandleIDs.append(handleID)
    }

    func releaseCount() -> Int {
        releasedHandleIDs.count
    }
}

private actor PendingPlanAuthorityEventStreaming: FileEventStreaming {
    private var stoppedSubscriptionIDs: [UUID] = []

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        throw PendingPlanAuthorityTestError.unexpectedCall
    }

    func stop(subscriptionID: UUID) async {
        stoppedSubscriptionIDs.append(subscriptionID)
    }
}

private struct PendingPlanAuthoritySnapshotReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        _ = access
        _ = generation
        throw PendingPlanAuthorityTestError.unexpectedCall
    }
}

private actor PendingPlanAuthorityDropPlanner: DropPlanning {
    private let result: DropPlan
    private var abandonedRequests: [AuthorizedCopyBatchRequest] = []

    init(result: DropPlan) {
        self.result = result
    }

    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        return result
    }

    func abandon(_ request: AuthorizedCopyBatchRequest) async {
        abandonedRequests.append(request)
    }

    func abandoned() -> [AuthorizedCopyBatchRequest] {
        abandonedRequests
    }
}

private actor PendingPlanAuthorityFileCopying: FileCopying {
    private var requests: [AuthorizedCopyBatchRequest] = []

    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        requests.append(request)
        return CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: request.plan.items.map {
                CopyItemSuccess(
                    operationID: $0.operationID,
                    destinationURL: request.destinationAccess.url
                        .appendingPathComponent($0.destinationFilename)
                )
            },
            failed: nil,
            notAttempted: []
        )
    }

    func callCount() -> Int {
        requests.count
    }
}

private struct PendingPlanAuthorityFixture {
    let session: GlassRuntimeSession
    let eventContinuation: AsyncStream<FileEvent>.Continuation
    let planner: PendingPlanAuthorityDropPlanner
    let fileCopying: PendingPlanAuthorityFileCopying
    let accessController: PendingPlanAuthorityAccessController
    let plan: CopyBatchPlan
    let access: FolderAccessHandle
}

private func makePendingPlanAuthorityFixture() throws -> PendingPlanAuthorityFixture {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassPendingPlanAuthority", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Pending Plan Authority",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
        placement: GlassPlacement(x: 30, y: 40),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let access = FolderAccessHandle(
        glassID: configuration.id,
        url: root,
        fingerprint: ResourceFingerprint(
            volumeIdentifier: "volume-A",
            resourceIdentifier: "folder-A"
        )
    )
    let initialSnapshot = FolderSnapshot(
        folderIdentity: FolderIdentity(
            resourceIdentifier: "folder-A",
            standardizedURL: root
        ),
        items: [],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_000),
        generation: 1
    )
    let source = URL(fileURLWithPath: "/tmp/External/pending-plan.txt")
    let plan = try CopyBatchPlan(
        destination: DestinationDescriptor(
            glassID: configuration.id,
            folderIdentity: initialSnapshot.folderIdentity,
            url: root,
            capabilities: StorageCapabilities(
                locationKind: .localFixed,
                isWritable: true,
                supportsCaseSensitiveNames: true,
                supportsSafeDestinationCommit: true
            )
        ),
        items: [
            CopyItemPlan(
                sourceURL: source,
                originalFilename: source.lastPathComponent,
                destinationFilename: source.lastPathComponent,
                expectedSize: 7
            )
        ]
    )
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let planner = PendingPlanAuthorityDropPlanner(result: .copy(plan))
    let fileCopying = PendingPlanAuthorityFileCopying()
    let accessController = PendingPlanAuthorityAccessController()
    let session = GlassRuntimeSession(
        seed: CreatedGlassRuntimeSeed(
            configuration: configuration,
            access: access,
            snapshot: initialSnapshot,
            eventSubscription: FileEventSubscription(
                id: UUID(),
                events: eventPair.stream
            )
        ),
        eventStreaming: PendingPlanAuthorityEventStreaming(),
        snapshotReader: PendingPlanAuthoritySnapshotReader(),
        accessController: accessController,
        dropPlanning: planner,
        fileCopying: fileCopying
    )

    return PendingPlanAuthorityFixture(
        session: session,
        eventContinuation: eventPair.continuation,
        planner: planner,
        fileCopying: fileCopying,
        accessController: accessController,
        plan: plan,
        access: access
    )
}

@Test
func runtimeStopAbandonsReturnedAuthoritativePlanBeforeAccessRelease() async throws {
    let fixture = try makePendingPlanAuthorityFixture()
    let states = try await fixture.session.start()
    _ = states

    let result = await fixture.session.planDrop(
        sourceURLs: fixture.plan.items.map(\.sourceURL)
    )
    #expect(result == .copy(fixture.plan))

    await fixture.session.stop()

    let abandoned = await fixture.planner.abandoned()
    #expect(abandoned.count == 1)
    #expect(abandoned.first?.plan == fixture.plan)
    #expect(abandoned.first?.destinationAccess == fixture.access)
    #expect(await fixture.fileCopying.callCount() == 0)
    #expect(await fixture.accessController.releaseCount() == 1)

    do {
        _ = try await fixture.session.executeCopy(fixture.plan)
        Issue.record("Expected sessionNotRunning")
    } catch let error as GlassCopyExecutionError {
        #expect(error == .sessionNotRunning)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await fixture.planner.abandoned().count == 1)
    fixture.eventContinuation.finish()
}

@Test
func admittedAuthoritativePlanTransfersCleanupOwnershipToFileCopying() async throws {
    let fixture = try makePendingPlanAuthorityFixture()
    let states = try await fixture.session.start()
    _ = states

    let result = await fixture.session.planDrop(
        sourceURLs: fixture.plan.items.map(\.sourceURL)
    )
    #expect(result == .copy(fixture.plan))

    let copyResult = try await fixture.session.executeCopy(fixture.plan)
    #expect(copyResult.failed == nil)
    #expect(await fixture.fileCopying.callCount() == 1)

    await fixture.session.stop()

    #expect(await fixture.planner.abandoned().isEmpty)
    #expect(await fixture.accessController.releaseCount() == 1)
    fixture.eventContinuation.finish()
}
