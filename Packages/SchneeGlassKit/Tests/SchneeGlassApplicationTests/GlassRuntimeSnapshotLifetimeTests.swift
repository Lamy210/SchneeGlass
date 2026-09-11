import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum SnapshotLifetimeTestError: Error, Sendable {
    case unexpectedCall
}

private actor SnapshotLifetimeAccessController: FolderAccessControlling {
    private var releasedHandleIDs: [UUID] = []

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        throw SnapshotLifetimeTestError.unexpectedCall
    }

    func release(handleID: UUID) async {
        releasedHandleIDs.append(handleID)
    }

    func releaseCount() -> Int {
        releasedHandleIDs.count
    }
}

private actor SnapshotLifetimeEventStreaming: FileEventStreaming {
    private var stoppedSubscriptionIDs: [UUID] = []

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        throw SnapshotLifetimeTestError.unexpectedCall
    }

    func stop(subscriptionID: UUID) async {
        stoppedSubscriptionIDs.append(subscriptionID)
    }

    func stopCount() -> Int {
        stoppedSubscriptionIDs.count
    }
}

private actor BlockingSnapshotLifetimeReader: FolderSnapshotReading {
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

private struct SnapshotLifetimeDropPlanner: DropPlanning {
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        return .noOperation
    }
}

private struct SnapshotLifetimeFileCopying: FileCopying {
    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [],
            failed: nil,
            notAttempted: request.plan.items
        )
    }
}

private func waitForSnapshotStart(_ reader: BlockingSnapshotLifetimeReader) async -> Bool {
    for _ in 0..<2_000 {
        if await reader.hasStarted() {
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForEventStop(_ streaming: SnapshotLifetimeEventStreaming) async -> Bool {
    for _ in 0..<2_000 {
        if await streaming.stopCount() > 0 {
            return true
        }
        await Task.yield()
    }
    return false
}

@Test
func runtimeStopKeepsFolderAccessUntilInFlightSnapshotReturns() async throws {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassSnapshotLifetime", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Snapshot Lifetime",
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
    let reader = BlockingSnapshotLifetimeReader()
    let accessController = SnapshotLifetimeAccessController()
    let eventStreaming = SnapshotLifetimeEventStreaming()
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
        dropPlanning: SnapshotLifetimeDropPlanner(),
        fileCopying: SnapshotLifetimeFileCopying()
    )

    let states = try await session.start()
    _ = states
    eventPair.continuation.yield(.changed)
    #expect(await waitForSnapshotStart(reader))

    let stopTask = Task {
        await session.stop()
    }
    #expect(await waitForEventStop(eventStreaming))

    // `stop()` has already cancelled the event loop and stopped new events, but the snapshot reader
    // is still deliberately suspended. The security-scoped folder authority must remain held.
    #expect(await accessController.releaseCount() == 0)

    await reader.finish()
    await stopTask.value

    #expect(await eventStreaming.stopCount() == 1)
    #expect(await accessController.releaseCount() == 1)

    eventPair.continuation.finish()
}
