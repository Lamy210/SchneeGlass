import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RuntimeSessionTestError: Error, Sendable {
    case injected
}

private actor RuntimeAccessController: FolderAccessControlling {
    private var releasedIDs: [UUID] = []

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        throw RuntimeSessionTestError.injected
    }

    func release(handleID: UUID) async {
        releasedIDs.append(handleID)
    }

    func releaseCount() -> Int {
        releasedIDs.count
    }
}

private actor RuntimeEventStreaming: FileEventStreaming {
    private var stoppedIDs: [UUID] = []

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        throw RuntimeSessionTestError.injected
    }

    func stop(subscriptionID: UUID) async {
        stoppedIDs.append(subscriptionID)
    }

    func stopCount() -> Int {
        stoppedIDs.count
    }
}

private actor RuntimeSnapshotReader: FolderSnapshotReading {
    enum Behavior: Sendable {
        case snapshot(FolderSnapshot)
        case fail
    }

    private var behaviors: [Behavior]

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        guard !behaviors.isEmpty else {
            throw RuntimeSessionTestError.injected
        }

        let behavior = behaviors.removeFirst()
        switch behavior {
        case let .snapshot(snapshot):
            return FolderSnapshot(
                folderIdentity: snapshot.folderIdentity,
                items: snapshot.items,
                isTruncated: snapshot.isTruncated,
                observedAt: snapshot.observedAt,
                generation: generation
            )
        case .fail:
            throw RuntimeSessionTestError.injected
        }
    }
}

private actor RuntimeDropPlanner: DropPlanning {
    private let result: DropPlan
    private var observedSourceURLs: [URL] = []
    private var observedAccess: FolderAccessHandle?

    init(result: DropPlan = .noOperation) {
        self.result = result
    }

    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        observedSourceURLs = sourceURLs
        observedAccess = destinationAccess
        return result
    }

    func observations() -> (sourceURLs: [URL], access: FolderAccessHandle?) {
        (observedSourceURLs, observedAccess)
    }
}

private actor RuntimeFileCopying: FileCopying {
    private let gate: AsyncStream<Void>?
    private var requests: [AuthorizedCopyBatchRequest] = []

    init(gate: AsyncStream<Void>? = nil) {
        self.gate = gate
    }

    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        requests.append(request)
        if let gate {
            var iterator = gate.makeAsyncIterator()
            _ = await iterator.next()
        }
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

    func lastRequest() -> AuthorizedCopyBatchRequest? {
        requests.last
    }
}

private struct RuntimeFixture {
    let session: GlassRuntimeSession
    let eventContinuation: AsyncStream<FileEvent>.Continuation
    let copyGateContinuation: AsyncStream<Void>.Continuation?
    let accessController: RuntimeAccessController
    let eventStreaming: RuntimeEventStreaming
    let dropPlanner: RuntimeDropPlanner
    let fileCopying: RuntimeFileCopying
    let configuration: GlassConfiguration
    let access: FolderAccessHandle
    let initialSnapshot: FolderSnapshot
}

private func makeRuntimeFixture(
    initialItems: [GlassItem] = [],
    refreshBehaviors: [RuntimeSnapshotReader.Behavior] = [],
    blockCopy: Bool = false
) throws -> RuntimeFixture {
    let root = URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
    let configuration = try GlassConfiguration(
        title: "Runtime",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: root.path),
        placement: try GlassPlacement(x: 100, y: 100),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let access = FolderAccessHandle(glassID: configuration.id, url: root)
    let initialSnapshot = FolderSnapshot(
        folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: root),
        items: initialItems,
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_001),
        generation: 1
    )
    let eventPair = AsyncStream<FileEvent>.makeStream()
    let subscription = FileEventSubscription(
        id: UUID(),
        events: eventPair.stream
    )
    let copyPair = blockCopy ? AsyncStream<Void>.makeStream() : nil
    let accessController = RuntimeAccessController()
    let eventStreaming = RuntimeEventStreaming()
    let reader = RuntimeSnapshotReader(behaviors: refreshBehaviors)
    let dropPlanner = RuntimeDropPlanner()
    let fileCopying = RuntimeFileCopying(gate: copyPair?.stream)
    let seed = CreatedGlassRuntimeSeed(
        configuration: configuration,
        access: access,
        snapshot: initialSnapshot,
        eventSubscription: subscription
    )

    return RuntimeFixture(
        session: GlassRuntimeSession(
            seed: seed,
            eventStreaming: eventStreaming,
            snapshotReader: reader,
            accessController: accessController,
            dropPlanning: dropPlanner,
            fileCopying: fileCopying
        ),
        eventContinuation: eventPair.continuation,
        copyGateContinuation: copyPair?.continuation,
        accessController: accessController,
        eventStreaming: eventStreaming,
        dropPlanner: dropPlanner,
        fileCopying: fileCopying,
        configuration: configuration,
        access: access,
        initialSnapshot: initialSnapshot
    )
}

private func item(named name: String) -> GlassItem {
    let url = URL(fileURLWithPath: "/tmp/SchneeGlassRuntime/\(name)")
    return GlassItem(
        id: FileIdentity(resourceIdentifier: nil, standardizedURL: url),
        url: url,
        displayName: name,
        kind: .regular,
        modificationDate: nil,
        fileSize: 1,
        isHidden: false
    )
}

private func copyPlan(for fixture: RuntimeFixture) throws -> CopyBatchPlan {
    let source = URL(fileURLWithPath: "/tmp/External/payload.txt")
    return try CopyBatchPlan(
        destination: DestinationDescriptor(
            glassID: fixture.configuration.id,
            folderIdentity: fixture.initialSnapshot.folderIdentity,
            url: fixture.access.url,
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
                expectedSize: 7
            )
        ]
    )
}

private func waitForCopyStart(_ copying: RuntimeFileCopying) async -> Bool {
    for _ in 0..<2_000 {
        if await copying.callCount() > 0 {
            return true
        }
        await Task.yield()
    }
    return false
}

private func waitForWatcherStop(_ streaming: RuntimeEventStreaming) async -> Bool {
    for _ in 0..<2_000 {
        if await streaming.stopCount() > 0 {
            return true
        }
        await Task.yield()
    }
    return false
}

@Test
func runtimeSessionImmediatelyPublishesInitialSnapshotAndRefreshesOnChange() async throws {
    let refreshed = FolderSnapshot(
        folderIdentity: FolderIdentity(
            resourceIdentifier: nil,
            standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
        ),
        items: [item(named: "updated.txt")],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_002),
        generation: 999
    )
    let fixture = try makeRuntimeFixture(
        refreshBehaviors: [.snapshot(refreshed)]
    )

    let states = try await fixture.session.start()
    var iterator = states.makeAsyncIterator()

    #expect(await iterator.next() == .empty(fixture.initialSnapshot))

    fixture.eventContinuation.yield(.changed)
    let updatedState = await iterator.next()

    guard case let .ready(snapshot)? = updatedState else {
        Issue.record("Expected ready state after filesystem change")
        return
    }
    #expect(snapshot.generation == 2)
    #expect(snapshot.items.map(\.displayName) == ["updated.txt"])

    await fixture.session.stop()
    #expect(await fixture.eventStreaming.stopCount() == 1)
    #expect(await fixture.accessController.releaseCount() == 1)
}

@Test
func runtimeSessionRecoversAfterTransientSnapshotFailure() async throws {
    let recovered = FolderSnapshot(
        folderIdentity: FolderIdentity(
            resourceIdentifier: nil,
            standardizedURL: URL(fileURLWithPath: "/tmp/SchneeGlassRuntime", isDirectory: true)
        ),
        items: [item(named: "recovered.txt")],
        isTruncated: false,
        observedAt: Date(timeIntervalSince1970: 1_700_000_003),
        generation: 999
    )
    let fixture = try makeRuntimeFixture(
        refreshBehaviors: [.fail, .snapshot(recovered)]
    )

    let states = try await fixture.session.start()
    var iterator = states.makeAsyncIterator()
    _ = await iterator.next()

    fixture.eventContinuation.yield(.changed)
    #expect(await iterator.next() == .failed(.enumerationFailed))

    fixture.eventContinuation.yield(.requiresFullRescan)
    let recoveredState = await iterator.next()
    guard case let .ready(snapshot)? = recoveredState else {
        Issue.record("Expected runtime to recover on the next filesystem event")
        return
    }
    #expect(snapshot.generation == 3)

    await fixture.session.stop()
}

@Test
func rootChangePublishesUnavailableThenStopsWatcherAndAccess() async throws {
    let fixture = try makeRuntimeFixture()
    let states = try await fixture.session.start()
    var iterator = states.makeAsyncIterator()
    _ = await iterator.next()

    fixture.eventContinuation.yield(.rootChanged)

    #expect(await iterator.next() == .unavailable(.sourceMissing))
    #expect(await iterator.next() == nil)
    #expect(await fixture.eventStreaming.stopCount() == 1)
    #expect(await fixture.accessController.releaseCount() == 1)
}

@Test
func runtimeStopIsIdempotentAndFinishesStateStream() async throws {
    let fixture = try makeRuntimeFixture()
    let states = try await fixture.session.start()
    var iterator = states.makeAsyncIterator()
    _ = await iterator.next()

    await fixture.session.stop()
    await fixture.session.stop()

    #expect(await iterator.next() == nil)
    #expect(await fixture.eventStreaming.stopCount() == 1)
    #expect(await fixture.accessController.releaseCount() == 1)
}

@Test
func runtimeSessionCannotBeStartedTwice() async throws {
    let fixture = try makeRuntimeFixture()
    let states = try await fixture.session.start()
    _ = states

    do {
        _ = try await fixture.session.start()
        Issue.record("Expected second start to fail")
    } catch let error as GlassRuntimeSessionError {
        #expect(error == .alreadyStarted)
    }

    await fixture.session.stop()
}

@Test
func runtimeDropPlanningUsesTheSessionsAuthorizedDestination() async throws {
    let fixture = try makeRuntimeFixture()
    let states = try await fixture.session.start()
    _ = states
    let sources = [URL(fileURLWithPath: "/tmp/External/report.txt")]

    let result = await fixture.session.planDrop(sourceURLs: sources)
    let observations = await fixture.dropPlanner.observations()

    #expect(result == .noOperation)
    #expect(observations.sourceURLs == sources)
    #expect(observations.access?.id == fixture.access.id)
    #expect(observations.access?.glassID == fixture.configuration.id)

    await fixture.session.stop()
}

@Test
func runtimeCopyRejectsPlanForAnotherDestinationBeforeMutation() async throws {
    let fixture = try makeRuntimeFixture()
    let states = try await fixture.session.start()
    _ = states
    let validPlan = try copyPlan(for: fixture)
    let otherURL = URL(fileURLWithPath: "/tmp/OtherGlass", isDirectory: true)
    let invalidPlan = try CopyBatchPlan(
        destination: DestinationDescriptor(
            glassID: GlassID(),
            folderIdentity: FolderIdentity(resourceIdentifier: nil, standardizedURL: otherURL),
            url: otherURL,
            capabilities: StorageCapabilities(locationKind: .localFixed, isWritable: true)
        ),
        items: validPlan.items
    )

    do {
        _ = try await fixture.session.executeCopy(invalidPlan)
        Issue.record("Expected destination mismatch")
    } catch let error as GlassCopyExecutionError {
        #expect(error == .destinationMismatch)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await fixture.fileCopying.callCount() == 0)
    await fixture.session.stop()
}

@Test
func runtimeRejectsSecondCopyWhileOneIsInProgress() async throws {
    let fixture = try makeRuntimeFixture(blockCopy: true)
    let states = try await fixture.session.start()
    _ = states
    let plan = try copyPlan(for: fixture)
    let session = fixture.session
    let firstCopy = Task {
        try await session.executeCopy(plan)
    }

    #expect(await waitForCopyStart(fixture.fileCopying))

    do {
        _ = try await session.executeCopy(plan)
        Issue.record("Expected concurrent copy rejection")
    } catch let error as GlassCopyExecutionError {
        #expect(error == .copyInProgress)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    fixture.copyGateContinuation?.yield(())
    fixture.copyGateContinuation?.finish()
    _ = try await firstCopy.value
    #expect(await fixture.fileCopying.callCount() == 1)

    await session.stop()
}

@Test
func runtimeStopWaitsForActiveCopyBeforeReleasingSecurityScope() async throws {
    let fixture = try makeRuntimeFixture(blockCopy: true)
    let states = try await fixture.session.start()
    _ = states
    let plan = try copyPlan(for: fixture)
    let session = fixture.session
    let copyTask = Task {
        try await session.executeCopy(plan)
    }

    #expect(await waitForCopyStart(fixture.fileCopying))

    let stopTask = Task {
        await session.stop()
    }
    #expect(await waitForWatcherStop(fixture.eventStreaming))
    #expect(await fixture.accessController.releaseCount() == 0)

    fixture.copyGateContinuation?.yield(())
    fixture.copyGateContinuation?.finish()
    _ = try await copyTask.value
    await stopTask.value

    #expect(await fixture.accessController.releaseCount() == 1)
    #expect(await fixture.eventStreaming.stopCount() == 1)
}

@Test
func runtimeCopyBeforeStartIsRejected() async throws {
    let fixture = try makeRuntimeFixture()
    let plan = try copyPlan(for: fixture)

    do {
        _ = try await fixture.session.executeCopy(plan)
        Issue.record("Expected session-not-running rejection")
    } catch let error as GlassCopyExecutionError {
        #expect(error == .sessionNotRunning)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await fixture.fileCopying.callCount() == 0)
    await fixture.session.stop()
}
