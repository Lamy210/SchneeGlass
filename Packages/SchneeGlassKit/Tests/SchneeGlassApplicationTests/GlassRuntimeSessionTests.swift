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

private struct RuntimeFixture {
    let session: GlassRuntimeSession
    let eventContinuation: AsyncStream<FileEvent>.Continuation
    let accessController: RuntimeAccessController
    let eventStreaming: RuntimeEventStreaming
    let initialSnapshot: FolderSnapshot
}

private func makeRuntimeFixture(
    initialItems: [GlassItem] = [],
    refreshBehaviors: [RuntimeSnapshotReader.Behavior] = []
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
    let accessController = RuntimeAccessController()
    let eventStreaming = RuntimeEventStreaming()
    let reader = RuntimeSnapshotReader(behaviors: refreshBehaviors)
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
            accessController: accessController
        ),
        eventContinuation: eventPair.continuation,
        accessController: accessController,
        eventStreaming: eventStreaming,
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
