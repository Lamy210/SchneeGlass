import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum SnapshotReplacementTestError: Error, Sendable {
    case unexpectedCall
}

private actor SnapshotReplacementAccessController: FolderAccessControlling {
    private var releaseCountValue = 0

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        throw SnapshotReplacementTestError.unexpectedCall
    }

    func release(handleID: UUID) async {
        releaseCountValue += 1
    }

    func releaseCount() -> Int {
        releaseCountValue
    }
}

private actor SnapshotReplacementEventStreaming: FileEventStreaming {
    private var stopCountValue = 0

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        throw SnapshotReplacementTestError.unexpectedCall
    }

    func stop(subscriptionID: UUID) async {
        stopCountValue += 1
    }

    func stopCount() -> Int {
        stopCountValue
    }
}

private struct SnapshotReplacementReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        throw FolderSnapshotReadError.rootIdentityMismatch
    }
}

private struct SnapshotReplacementDropPlanner: DropPlanning {
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        .noOperation
    }
}

private struct SnapshotReplacementFileCopying: FileCopying {
    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [],
            failed: nil,
            notAttempted: request.plan.items
        )
    }
}

@Test
func snapshotRootReplacementPublishesUnavailableAndTerminallyStopsRuntime() async throws {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassSnapshotReplacement", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Replacement",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
        placement: try GlassPlacement(x: 100, y: 100),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let access = FolderAccessHandle(glassID: configuration.id, url: root)
    let initialSnapshot = FolderSnapshot(
        folderIdentity: FolderIdentity(resourceIdentifier: "original-root", standardizedURL: root),
        items: [],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_001),
        generation: 1
    )
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let accessController = SnapshotReplacementAccessController()
    let eventStreaming = SnapshotReplacementEventStreaming()
    let session = GlassRuntimeSession(
        seed: CreatedGlassRuntimeSeed(
            configuration: configuration,
            access: access,
            snapshot: initialSnapshot,
            eventSubscription: FileEventSubscription(events: eventPair.stream)
        ),
        eventStreaming: eventStreaming,
        snapshotReader: SnapshotReplacementReader(),
        accessController: accessController,
        dropPlanning: SnapshotReplacementDropPlanner(),
        fileCopying: SnapshotReplacementFileCopying()
    )

    let states = try await session.start()
    var iterator = states.makeAsyncIterator()
    #expect(await iterator.next() == .empty(initialSnapshot))

    eventPair.continuation.yield(.changed)

    #expect(await iterator.next() == .unavailable(.replacementDetected))
    #expect(await iterator.next() == nil)
    #expect(await eventStreaming.stopCount() == 1)
    #expect(await accessController.releaseCount() == 1)
    #expect(await session.planDrop(sourceURLs: []) == .reject(.destinationUnavailable))

    await session.stop()
    await session.stop()

    #expect(await eventStreaming.stopCount() == 1)
    #expect(await accessController.releaseCount() == 1)
}
