import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum ConcurrentStopTestError: Error, Sendable {
    case unexpectedCall
}

private actor ConcurrentStopAccessController: FolderAccessControlling {
    private var releasedHandleIDs: [UUID] = []

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        throw ConcurrentStopTestError.unexpectedCall
    }

    func release(handleID: UUID) async {
        releasedHandleIDs.append(handleID)
    }

    func releaseCount() -> Int {
        releasedHandleIDs.count
    }
}

private actor ConcurrentStopEventStreaming: FileEventStreaming {
    private var stoppedSubscriptionIDs: [UUID] = []

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        throw ConcurrentStopTestError.unexpectedCall
    }

    func stop(subscriptionID: UUID) async {
        stoppedSubscriptionIDs.append(subscriptionID)
    }

    func stopCount() -> Int {
        stoppedSubscriptionIDs.count
    }
}

private actor ConcurrentStopSnapshotReader: FolderSnapshotReading {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }

        return FolderSnapshot(
            folderIdentity: FolderIdentity(
                resourceIdentifier: access.fingerprint?.resourceIdentifier,
                standardizedURL: access.url
            ),
            items: [],
            isTruncated: false,
            observedAt: Date(timeIntervalSince1970: 1_700_000_001),
            generation: generation
        )
    }

    func hasStarted() -> Bool {
        started
    }

    func finish() {
        continuation?.resume()
        continuation = nil
    }
}

private struct ConcurrentStopDropPlanner: DropPlanning {
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        return .noOperation
    }
}

private struct ConcurrentStopFileCopying: FileCopying {
    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [],
            failed: nil,
            notAttempted: request.plan.items
        )
    }
}

private actor ConcurrentStopProbe {
    private var startedCount = 0
    private var completedCount = 0

    func markStarted() {
        startedCount += 1
    }

    func markCompleted() {
        completedCount += 1
    }

    func state() -> (started: Int, completed: Int) {
        (startedCount, completedCount)
    }
}

private func waitForConcurrentStopSnapshot(
    _ reader: ConcurrentStopSnapshotReader
) async -> Bool {
    for _ in 0..<2_000 {
        if await reader.hasStarted() {
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForConcurrentStopSubscription(
    _ streaming: ConcurrentStopEventStreaming
) async -> Bool {
    for _ in 0..<2_000 {
        if await streaming.stopCount() > 0 {
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForSecondStopToEnter(_ probe: ConcurrentStopProbe) async -> Bool {
    for _ in 0..<2_000 {
        if await probe.state().started > 0 {
            return true
        }
        await Task.yield()
    }
    return false
}

@Test
func concurrentRuntimeStopJoinsExistingCleanup() async throws {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassConcurrentStop", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Concurrent Stop",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
        placement: GlassPlacement(x: 10, y: 20),
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
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let reader = ConcurrentStopSnapshotReader()
    let accessController = ConcurrentStopAccessController()
    let eventStreaming = ConcurrentStopEventStreaming()
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
        eventStreaming: eventStreaming,
        snapshotReader: reader,
        accessController: accessController,
        dropPlanning: ConcurrentStopDropPlanner(),
        fileCopying: ConcurrentStopFileCopying()
    )

    let states = try await session.start()
    _ = states
    eventPair.continuation.yield(.changed)
    #expect(await waitForConcurrentStopSnapshot(reader))

    let firstStop = Task {
        await session.stop()
    }
    #expect(await waitForConcurrentStopSubscription(eventStreaming))
    #expect(await accessController.releaseCount() == 0)

    let probe = ConcurrentStopProbe()
    let secondStop = Task {
        await probe.markStarted()
        await session.stop()
        await probe.markCompleted()
    }
    #expect(await waitForSecondStopToEnter(probe))

    // Give the second caller ample scheduling opportunities. It must remain suspended until the
    // first stop finishes the blocked snapshot and releases the folder authority.
    for _ in 0..<200 {
        await Task.yield()
    }
    #expect(await probe.state().completed == 0)
    #expect(await accessController.releaseCount() == 0)

    await reader.finish()
    await firstStop.value
    await secondStop.value

    #expect(await probe.state().completed == 1)
    #expect(await accessController.releaseCount() == 1)
    #expect(await eventStreaming.stopCount() == 1)

    eventPair.continuation.finish()
}
