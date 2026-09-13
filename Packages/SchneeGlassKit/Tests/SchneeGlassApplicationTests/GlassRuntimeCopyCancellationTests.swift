import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RuntimeCopyCancellationTestError: Error, Sendable {
    case unreachable
}

private actor RuntimeCopyCancellationAccessController: FolderAccessControlling {
    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        throw RuntimeCopyCancellationTestError.unreachable
    }

    func release(handleID: UUID) async {
        _ = handleID
    }
}

private actor RuntimeCopyCancellationEventStreaming: FileEventStreaming {
    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        throw RuntimeCopyCancellationTestError.unreachable
    }

    func stop(subscriptionID: UUID) async {
        _ = subscriptionID
    }
}

private actor RuntimeCopyCancellationSnapshotReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        _ = access
        _ = generation
        throw RuntimeCopyCancellationTestError.unreachable
    }
}

private actor RuntimeCopyCancellationDropPlanner: DropPlanning {
    private var plans: [CopyBatchPlan]

    init(plans: [CopyBatchPlan]) {
        self.plans = plans
    }

    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        guard !plans.isEmpty else {
            return .noOperation
        }
        return .copy(plans.removeFirst())
    }
}

private actor CancellationObservingFileCopying: FileCopying {
    private var started = false
    private var observedCancellation = false

    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        started = true
        while !Task.isCancelled {
            await Task.yield()
        }
        observedCancellation = true

        let first = request.plan.items[0]
        return CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [],
            failed: CopyItemFailure(operationID: first.operationID, reason: .cancelled),
            notAttempted: Array(request.plan.items.dropFirst())
        )
    }

    func hasStarted() -> Bool {
        started
    }

    func didObserveCancellation() -> Bool {
        observedCancellation
    }
}

private actor ImmediateSuccessFileCopying: FileCopying {
    private var invocationCountValue = 0

    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        invocationCountValue += 1
        return CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: request.plan.items.map { item in
                CopyItemSuccess(
                    operationID: item.operationID,
                    destinationURL: request.plan.destination.url
                        .appendingPathComponent(item.destinationFilename, isDirectory: false)
                )
            },
            failed: nil,
            notAttempted: []
        )
    }

    func invocationCount() -> Int {
        invocationCountValue
    }
}

private func makeRuntimeCopyCancellationFixture<C: FileCopying>(
    copying: C,
    planCount: Int
) throws -> (
    session: GlassRuntimeSession,
    plans: [CopyBatchPlan],
    eventContinuation: AsyncStream<FileEvent>.Continuation
) {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassRuntimeCancellation", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Cancellation",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
        placement: try GlassPlacement(x: 100, y: 100),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let access = FolderAccessHandle(glassID: configuration.id, url: root)
    let snapshot = FolderSnapshot(
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: root),
        items: [],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_001),
        generation: 1
    )
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let seed = CreatedGlassRuntimeSeed(
        configuration: configuration,
        access: access,
        snapshot: snapshot,
        eventSubscription: FileEventSubscription(events: eventPair.stream)
    )
    let destination = DestinationDescriptor(
        glassID: configuration.id,
        folderIdentity: snapshot.folderIdentity,
        url: root,
        capabilities: StorageCapabilities(
            locationKind: .localFixed,
            isWritable: true,
            supportsCaseSensitiveNames: false
        )
    )
    let plans = try (0..<planCount).map { index in
        let source = URL(fileURLWithPath: "/tmp/runtime-cancel-\(index).txt")
        return try CopyBatchPlan(
            destination: destination,
            items: [
                CopyItemPlan(
                    sourceURL: source,
                    originalFilename: source.lastPathComponent,
                    destinationFilename: source.lastPathComponent,
                    expectedSize: 1
                )
            ]
        )
    }

    return (
        session: GlassRuntimeSession(
            seed: seed,
            eventStreaming: RuntimeCopyCancellationEventStreaming(),
            snapshotReader: RuntimeCopyCancellationSnapshotReader(),
            accessController: RuntimeCopyCancellationAccessController(),
            dropPlanning: RuntimeCopyCancellationDropPlanner(plans: plans),
            fileCopying: copying
        ),
        plans: plans,
        eventContinuation: eventPair.continuation
    )
}

private func waitForRuntimeCopyStart(_ copying: CancellationObservingFileCopying) async -> Bool {
    for _ in 0..<2_000 {
        if await copying.hasStarted() {
            return true
        }
        await Task.yield()
    }
    return false
}

@Test
func runtimeSessionCancelCopyCancelsTheActiveCopyTask() async throws {
    let copying = CancellationObservingFileCopying()
    let fixture = try makeRuntimeCopyCancellationFixture(copying: copying, planCount: 1)
    let states = try await fixture.session.start()
    _ = states
    let session = fixture.session

    let planned = await session.planDrop(sourceURLs: fixture.plans[0].items.map(\.sourceURL))
    guard case let .copy(plan) = planned else {
        Issue.record("Expected authoritative copy plan")
        return
    }

    let execution = Task {
        try await session.executeCopy(plan)
    }

    #expect(await waitForRuntimeCopyStart(copying))
    await session.cancelCopy()

    let result = try await execution.value
    #expect(result.failed?.reason == .cancelled)
    #expect(await copying.didObserveCancellation())

    fixture.eventContinuation.finish()
    await session.stop()
}

@Test
func runtimeSessionPreservesCancellationRequestedBeforeCopyTaskRegistration() async throws {
    let copying = ImmediateSuccessFileCopying()
    let fixture = try makeRuntimeCopyCancellationFixture(copying: copying, planCount: 2)
    let states = try await fixture.session.start()
    _ = states
    let session = fixture.session

    let firstPlanned = await session.planDrop(sourceURLs: fixture.plans[0].items.map(\.sourceURL))
    guard case let .copy(firstPlan) = firstPlanned else {
        Issue.record("Expected first authoritative copy plan")
        return
    }

    await session.cancelCopy()
    let cancelledResult = try await session.executeCopy(firstPlan)

    #expect(cancelledResult.failed?.reason == .cancelled)
    #expect(cancelledResult.succeeded.isEmpty)
    #expect(await copying.invocationCount() == 0)

    let secondPlanned = await session.planDrop(sourceURLs: fixture.plans[1].items.map(\.sourceURL))
    guard case let .copy(secondPlan) = secondPlanned else {
        Issue.record("Expected fresh authoritative copy plan")
        return
    }

    let freshResult = try await session.executeCopy(secondPlan)

    #expect(freshResult.failed == nil)
    #expect(freshResult.succeeded.count == 1)
    #expect(await copying.invocationCount() == 1)

    fixture.eventContinuation.finish()
    await session.stop()
}
