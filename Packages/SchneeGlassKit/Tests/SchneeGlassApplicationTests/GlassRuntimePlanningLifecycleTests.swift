import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum PlanningLifecycleTestError: Error, Sendable {
    case unexpectedCall
}

private actor PlanningLifecycleAccessController: FolderAccessControlling {
    private var releasedHandleIDs: [UUID] = []

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        throw PlanningLifecycleTestError.unexpectedCall
    }

    func release(handleID: UUID) async {
        releasedHandleIDs.append(handleID)
    }

    func releases() -> [UUID] {
        releasedHandleIDs
    }
}

private actor PlanningLifecycleEventStreaming: FileEventStreaming {
    private var stoppedSubscriptionIDs: [UUID] = []

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        throw PlanningLifecycleTestError.unexpectedCall
    }

    func stop(subscriptionID: UUID) async {
        stoppedSubscriptionIDs.append(subscriptionID)
    }
}

private struct PlanningLifecycleSnapshotReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        _ = access
        _ = generation
        throw PlanningLifecycleTestError.unexpectedCall
    }
}

private actor BlockingLifecycleDropPlanner: DropPlanning {
    private let result: DropPlan
    private let planGate: AsyncStream<Void>
    private var planStarted = false
    private var abandonedRequests: [AuthorizedCopyBatchRequest] = []

    init(result: DropPlan, planGate: AsyncStream<Void>) {
        self.result = result
        self.planGate = planGate
    }

    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        planStarted = true
        var iterator = planGate.makeAsyncIterator()
        _ = await iterator.next()
        return result
    }

    func abandon(_ request: AuthorizedCopyBatchRequest) async {
        abandonedRequests.append(request)
    }

    func hasStartedPlanning() -> Bool {
        planStarted
    }

    func abandoned() -> [AuthorizedCopyBatchRequest] {
        abandonedRequests
    }
}

private actor PlanningLifecycleFileCopying: FileCopying {
    private var callCountValue = 0

    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        callCountValue += 1
        return CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [],
            failed: nil,
            notAttempted: request.plan.items
        )
    }

    func callCount() -> Int {
        callCountValue
    }
}

private func waitForPlanningStart(_ planner: BlockingLifecycleDropPlanner) async -> Bool {
    for _ in 0..<2_000 {
        if await planner.hasStartedPlanning() {
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForAccessRelease(_ accessController: PlanningLifecycleAccessController) async -> Bool {
    for _ in 0..<2_000 {
        if await accessController.releases().count > 0 {
            return true
        }
        await Task.yield()
    }
    return false
}

private func makePlanningLifecycleFixture() throws -> (
    configuration: GlassConfiguration,
    access: FolderAccessHandle,
    snapshot: FolderSnapshot,
    source: URL,
    copyPlan: CopyBatchPlan
) {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassPlanningLifecycle", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Planning Lifecycle",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
        placement: try GlassPlacement(x: 100, y: 100),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let access = FolderAccessHandle(glassID: configuration.id, url: root)
    let snapshot = FolderSnapshot(
        folderIdentity: FolderIdentity(resourceIdentifier: "destination", standardizedURL: root),
        items: [],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_001),
        generation: 1
    )
    let source = URL(fileURLWithPath: "/tmp/External/planning-race.txt")
    let destination = DestinationDescriptor(
        glassID: configuration.id,
        folderIdentity: snapshot.folderIdentity,
        url: root,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: true,
            supportsSafeDestinationCommit: true
        )
    )
    let copyPlan = try CopyBatchPlan(
        destination: destination,
        items: [
            CopyItemPlan(
                sourceURL: source,
                originalFilename: source.lastPathComponent,
                destinationFilename: source.lastPathComponent,
                expectedSize: 7
            )
        ]
    )
    return (configuration, access, snapshot, source, copyPlan)
}

@Test
func authoritativePlanCompletedAfterRuntimeStopIsAbandonedBeforeReturning() async throws {
    let fixture = try makePlanningLifecycleFixture()
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let planGatePair = AsyncStream<Void>.makeStream()
    let planner = BlockingLifecycleDropPlanner(
        result: .copy(fixture.copyPlan),
        planGate: planGatePair.stream
    )
    let accessController = PlanningLifecycleAccessController()
    let fileCopying = PlanningLifecycleFileCopying()
    let subscriptionID = UUID()
    let session = GlassRuntimeSession(
        seed: CreatedGlassRuntimeSeed(
            configuration: fixture.configuration,
            access: fixture.access,
            snapshot: fixture.snapshot,
            eventSubscription: FileEventSubscription(
                id: subscriptionID,
                events: eventPair.stream
            )
        ),
        eventStreaming: PlanningLifecycleEventStreaming(),
        snapshotReader: PlanningLifecycleSnapshotReader(),
        accessController: accessController,
        dropPlanning: planner,
        fileCopying: fileCopying
    )

    let states = try await session.start()
    _ = states

    let planningTask = Task {
        await session.planDrop(sourceURLs: [fixture.source])
    }
    #expect(await waitForPlanningStart(planner))

    let stopTask = Task {
        await session.stop()
    }
    #expect(await waitForAccessRelease(accessController))
    await stopTask.value

    planGatePair.continuation.yield(())
    planGatePair.continuation.finish()

    let result = await planningTask.value
    #expect(result == .reject(.destinationUnavailable))
    #expect(await fileCopying.callCount() == 0)
    #expect(await accessController.releases() == [fixture.access.id])

    let abandoned = await planner.abandoned()
    #expect(abandoned.count == 1)
    #expect(abandoned.first?.plan == fixture.copyPlan)
    #expect(abandoned.first?.destinationAccess == fixture.access)

    eventPair.continuation.finish()
}

@Test
func authoritativePlanCanBeExplicitlyAbandonedExactlyOnce() async throws {
    let fixture = try makePlanningLifecycleFixture()
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let planGatePair = AsyncStream<Void>.makeStream()
    let planner = BlockingLifecycleDropPlanner(
        result: .copy(fixture.copyPlan),
        planGate: planGatePair.stream
    )
    let accessController = PlanningLifecycleAccessController()
    let fileCopying = PlanningLifecycleFileCopying()
    let session = GlassRuntimeSession(
        seed: CreatedGlassRuntimeSeed(
            configuration: fixture.configuration,
            access: fixture.access,
            snapshot: fixture.snapshot,
            eventSubscription: FileEventSubscription(events: eventPair.stream)
        ),
        eventStreaming: PlanningLifecycleEventStreaming(),
        snapshotReader: PlanningLifecycleSnapshotReader(),
        accessController: accessController,
        dropPlanning: planner,
        fileCopying: fileCopying
    )

    let states = try await session.start()
    _ = states

    let planningTask = Task {
        await session.planDrop(sourceURLs: [fixture.source])
    }
    #expect(await waitForPlanningStart(planner))
    planGatePair.continuation.yield(())
    planGatePair.continuation.finish()

    let planned = await planningTask.value
    guard case let .copy(copyPlan) = planned else {
        Issue.record("Expected authoritative copy plan")
        await session.stop()
        eventPair.continuation.finish()
        return
    }

    await session.abandonCopyPlan(copyPlan)
    await session.abandonCopyPlan(copyPlan)

    let abandoned = await planner.abandoned()
    #expect(abandoned.count == 1)
    #expect(abandoned.first?.plan == fixture.copyPlan)
    #expect(abandoned.first?.destinationAccess == fixture.access)
    #expect(await fileCopying.callCount() == 0)

    await session.stop()
    #expect(await accessController.releases() == [fixture.access.id])
    eventPair.continuation.finish()
}
