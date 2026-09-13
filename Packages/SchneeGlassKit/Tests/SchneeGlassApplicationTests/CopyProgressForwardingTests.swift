import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum CopyProgressForwardingTestError: Error, Sendable {
    case unreachable
}

private actor ProgressForwardingAccessController: FolderAccessControlling {
    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        throw CopyProgressForwardingTestError.unreachable
    }

    func release(handleID: UUID) async {
        _ = handleID
    }
}

private actor ProgressForwardingEventStreaming: FileEventStreaming {
    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        _ = access
        throw CopyProgressForwardingTestError.unreachable
    }

    func stop(subscriptionID: UUID) async {
        _ = subscriptionID
    }
}

private actor ProgressForwardingSnapshotReader: FolderSnapshotReading {
    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        _ = access
        _ = generation
        throw CopyProgressForwardingTestError.unreachable
    }
}

private actor ProgressForwardingDropPlanner: DropPlanning {
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        _ = sourceURLs
        _ = destinationAccess
        return .noOperation
    }
}

private actor ProgressForwardingRecorder {
    private var values: [CopyProgress] = []

    func record(_ progress: CopyProgress) {
        values.append(progress)
    }

    func snapshot() -> [CopyProgress] {
        values
    }
}

private actor ProgressEmittingFileCopying: FileCopying {
    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        successfulResult(for: request)
    }

    func copy(
        _ request: AuthorizedCopyBatchRequest,
        onProgress: @escaping CopyProgressHandler
    ) async -> CopyBatchResult {
        for (index, item) in request.plan.items.enumerated() {
            await onProgress(
                CopyProgress(
                    currentIndex: index + 1,
                    totalCount: request.plan.items.count,
                    currentFilename: item.destinationFilename
                )
            )
        }
        return successfulResult(for: request)
    }

    private func successfulResult(
        for request: AuthorizedCopyBatchRequest
    ) -> CopyBatchResult {
        CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: request.plan.items.map { item in
                CopyItemSuccess(
                    operationID: item.operationID,
                    destinationURL: request.destinationAccess.url
                        .appendingPathComponent(item.destinationFilename)
                )
            },
            failed: nil,
            notAttempted: []
        )
    }
}

private actor ProgressForwardingAbandoner: AuthorizedCopyBatchAbandoning {
    func abandon(_ request: AuthorizedCopyBatchRequest) async {
        _ = request
    }
}

private func makeProgressForwardingFixture() throws -> (
    session: GlassRuntimeSession,
    plan: CopyBatchPlan,
    eventContinuation: AsyncStream<FileEvent>.Continuation
) {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassProgressForwarding", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Progress",
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
    let sources = [
        URL(fileURLWithPath: "/tmp/progress-one.txt"),
        URL(fileURLWithPath: "/tmp/progress-two.txt"),
    ]
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
        items: sources.map { source in
            CopyItemPlan(
                sourceURL: source,
                originalFilename: source.lastPathComponent,
                destinationFilename: source.lastPathComponent,
                expectedSize: 1
            )
        }
    )
    let session = GlassRuntimeSession(
        seed: seed,
        eventStreaming: ProgressForwardingEventStreaming(),
        snapshotReader: ProgressForwardingSnapshotReader(),
        accessController: ProgressForwardingAccessController(),
        dropPlanning: ProgressForwardingDropPlanner(),
        fileCopying: ProgressEmittingFileCopying()
    )
    return (session, plan, eventPair.continuation)
}

private func progressForwardingRequest() throws -> AuthorizedCopyBatchRequest {
    let destination = URL(fileURLWithPath: "/tmp/SchneeGlassProgressGate", isDirectory: true)
    let glassID = GlassID()
    let source = URL(fileURLWithPath: "/tmp/progress-gate.txt")
    let plan = try CopyBatchPlan(
        destination: DestinationDescriptor(
            glassID: glassID,
            folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: destination),
            url: destination,
            capabilities: StorageCapabilities(locationKind: .localFixed, isWritable: true)
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
    return AuthorizedCopyBatchRequest(
        plan: plan,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: destination)
    )
}

@Test
func runtimeSessionForwardsCopyProgressFromFileCopying() async throws {
    let fixture = try makeProgressForwardingFixture()
    let recorder = ProgressForwardingRecorder()
    _ = try await fixture.session.start()

    let result = try await fixture.session.executeCopy(fixture.plan) { progress in
        await recorder.record(progress)
    }

    #expect(result.failed == nil)
    #expect(
        await recorder.snapshot() == [
            CopyProgress(
                currentIndex: 1,
                totalCount: 2,
                currentFilename: "progress-one.txt"
            ),
            CopyProgress(
                currentIndex: 2,
                totalCount: 2,
                currentFilename: "progress-two.txt"
            ),
        ]
    )

    fixture.eventContinuation.finish()
    await fixture.session.stop()
}

@Test
func activityTrackedCopyForwardsProgressWhenCopyIsAdmitted() async throws {
    let request = try progressForwardingRequest()
    let recorder = ProgressForwardingRecorder()
    let tracked = ActivityTrackedFileCopying(
        delegate: ProgressEmittingFileCopying(),
        abandoner: ProgressForwardingAbandoner(),
        activityGate: FileOperationActivityGate()
    )

    let result = await tracked.copy(request) { progress in
        await recorder.record(progress)
    }

    #expect(result.failed == nil)
    #expect(
        await recorder.snapshot() == [
            CopyProgress(
                currentIndex: 1,
                totalCount: 1,
                currentFilename: "progress-gate.txt"
            ),
        ]
    )
}
