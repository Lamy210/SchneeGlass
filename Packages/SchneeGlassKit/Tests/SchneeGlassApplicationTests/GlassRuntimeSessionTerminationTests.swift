import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum EventStreamTerminationTestError: Error {
    case unexpectedCall
}

private actor TerminationAccessController: FolderAccessControlling {
    private var releaseCountValue = 0

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        throw EventStreamTerminationTestError.unexpectedCall
    }

    func release(handleID: UUID) async {
        releaseCountValue += 1
    }

    func releaseCount() -> Int {
        releaseCountValue
    }
}

private actor TerminationEventStreaming: FileEventStreaming {
    private var stopCountValue = 0

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        throw EventStreamTerminationTestError.unexpectedCall
    }

    func stop(subscriptionID: UUID) async {
        stopCountValue += 1
    }

    func stopCount() -> Int {
        stopCountValue
    }
}

private struct TerminationSnapshotReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        throw EventStreamTerminationTestError.unexpectedCall
    }
}

private struct TerminationDropPlanner: DropPlanning {
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        .noOperation
    }
}

private struct TerminationFileCopying: FileCopying {
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
func unexpectedEventStreamTerminationPublishesFailureBeforeStoppingSession() async throws {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassTermination", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Termination",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
        placement: try GlassPlacement(x: 100, y: 100),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let access = FolderAccessHandle(glassID: configuration.id, url: root)
    let initialSnapshot = FolderSnapshot(
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: root),
        items: [],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_001),
        generation: 1
    )
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let accessController = TerminationAccessController()
    let eventStreaming = TerminationEventStreaming()
    let session = GlassRuntimeSession(
        seed: CreatedGlassRuntimeSeed(
            configuration: configuration,
            access: access,
            snapshot: initialSnapshot,
            eventSubscription: FileEventSubscription(events: eventPair.stream)
        ),
        eventStreaming: eventStreaming,
        snapshotReader: TerminationSnapshotReader(),
        accessController: accessController,
        dropPlanning: TerminationDropPlanner(),
        fileCopying: TerminationFileCopying()
    )

    let states = try await session.start()
    var iterator = states.makeAsyncIterator()
    #expect(await iterator.next() == .empty(initialSnapshot))

    eventPair.continuation.finish()

    #expect(await iterator.next() == .failed(.unexpected))
    #expect(await iterator.next() == nil)
    #expect(await eventStreaming.stopCount() == 1)
    #expect(await accessController.releaseCount() == 1)
    #expect(await session.planDrop(sourceURLs: []) == .reject(.destinationUnavailable))
}
