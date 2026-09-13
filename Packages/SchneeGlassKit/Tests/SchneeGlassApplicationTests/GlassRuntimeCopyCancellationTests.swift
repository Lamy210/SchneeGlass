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
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        return .noOperation
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

private func makeRuntimeCopyCancellationFixture() throws -> (
    session: GlassRuntimeSession,
    plan: CopyBatchPlan,
    copying: CancellationObservingFileCopying,
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
    let copying = CancellationObservingFileCopying()
    let seed = CreatedGlassRuntimeSeed(
        configuration: configuration,
        access: access,
        snapshot: snapshot,
        eventSubscription: FileEventSubscription(events: eventPair.stream)
    )
    let source = URL(fileURLWithPath: "/tmp/runtime-cancel.txt")
    let plan = try CopyBatchPlan(
        destination: DestinationDescriptor(
            glassID: configuration.id,
            folderIdentity: snapshot.folderIdentity,
            url: root,
            capabilities: StorageCapabilities(
                locationKind: .localFixed,
                isWritable: true,
                supportsCaseSensitiveNames: false
            )
        ),
        items: [
            CopyItemPlan(
                sourceURL: source,
                originalFilename: source.lastPathComponent,
                destinationFilename: source.lastPathComponent,
                expectedSize: 1
            )
        ]
    )

    return (
        session: GlassRuntimeSession(
            seed: seed,
            eventStreaming: RuntimeCopyCancellationEventStreaming(),
            snapshotReader: RuntimeCopyCancellationSnapshotReader(),
            accessController: RuntimeCopyCancellationAccessController(),
            dropPlanning: RuntimeCopyCancellationDropPlanner(),
            fileCopying: copying
        ),
        plan: plan,
        copying: copying,
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
    let fixture = try makeRuntimeCopyCancellationFixture()
    let states = try await fixture.session.start()
    _ = states
    let session = fixture.session
    let plan = fixture.plan

    let execution = Task {
        try await session.executeCopy(plan)
    }

    #expect(await waitForRuntimeCopyStart(fixture.copying))
    await session.cancelCopy()

    let result = try await execution.value
    #expect(result.failed?.reason == .cancelled)
    #expect(await fixture.copying.didObserveCancellation())

    fixture.eventContinuation.finish()
    await session.stop()
}
