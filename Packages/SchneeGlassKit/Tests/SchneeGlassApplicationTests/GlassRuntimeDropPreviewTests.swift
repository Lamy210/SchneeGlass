import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor PreviewRecordingDropPlanner: DropPlanning {
    private var previewCount = 0
    private var planCount = 0
    private var lastPreviewAccess: FolderAccessHandle?
    private var lastPlanAccess: FolderAccessHandle?

    func preview(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        previewCount += 1
        lastPreviewAccess = destinationAccess
        return .reject(.collision)
    }

    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        planCount += 1
        lastPlanAccess = destinationAccess
        return .noOperation
    }

    func observations() -> (
        previewCount: Int,
        planCount: Int,
        previewAccess: FolderAccessHandle?,
        planAccess: FolderAccessHandle?
    ) {
        (previewCount, planCount, lastPreviewAccess, lastPlanAccess)
    }
}

private actor PreviewNoopEventStreaming: FileEventStreaming {
    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        return FileEventSubscription(id: UUID(), events: AsyncStream { $0.finish() })
    }

    func stop(subscriptionID: UUID) async {
        _ = subscriptionID
    }
}

private actor PreviewNoopSnapshotReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        FolderSnapshot(
            folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: access.url),
            items: [],
            isTruncated: false,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            generation: generation
        )
    }
}

private actor PreviewNoopAccessController: FolderAccessControlling {
    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        throw PreviewTestError.unused
    }

    func release(handleID: UUID) async {
        _ = handleID
    }
}

private actor PreviewNoopFileCopying: FileCopying {
    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [],
            failed: nil,
            notAttempted: request.plan.items
        )
    }
}

private enum PreviewTestError: Error {
    case unused
}

@Test
func runtimeSessionSeparatesHoverPreviewFromAuthoritativePlanning() async throws {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassPreviewRuntime", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Preview Runtime",
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
    let planner = PreviewRecordingDropPlanner()
    let session = GlassRuntimeSession(
        seed: CreatedGlassRuntimeSeed(
            configuration: configuration,
            access: access,
            snapshot: initialSnapshot,
            eventSubscription: FileEventSubscription(id: UUID(), events: eventPair.stream)
        ),
        eventStreaming: PreviewNoopEventStreaming(),
        snapshotReader: PreviewNoopSnapshotReader(),
        accessController: PreviewNoopAccessController(),
        dropPlanning: planner,
        fileCopying: PreviewNoopFileCopying()
    )
    let states = try await session.start()
    _ = states
    let sources = [URL(fileURLWithPath: "/tmp/External/preview.txt")]

    let preview = await session.previewDrop(sourceURLs: sources)
    #expect(preview == .reject(.collision))

    var observations = await planner.observations()
    #expect(observations.previewCount == 1)
    #expect(observations.planCount == 0)
    #expect(observations.previewAccess?.id == access.id)

    let authoritative = await session.planDrop(sourceURLs: sources)
    #expect(authoritative == .noOperation)

    observations = await planner.observations()
    #expect(observations.previewCount == 1)
    #expect(observations.planCount == 1)
    #expect(observations.planAccess?.id == access.id)

    eventPair.continuation.finish()
    await session.stop()
}
