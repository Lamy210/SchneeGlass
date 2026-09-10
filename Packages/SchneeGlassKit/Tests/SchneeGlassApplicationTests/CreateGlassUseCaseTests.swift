import FileDomain
import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum CreateGlassTestError: Error, Sendable {
    case injected
}

private actor CreateGlassTrace {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

@MainActor
private final class FakeFolderSelector: FolderSelecting {
    let url: URL?
    let trace: CreateGlassTrace

    init(url: URL?, trace: CreateGlassTrace) {
        self.url = url
        self.trace = trace
    }

    func selectFolder() async -> URL? {
        await trace.append("select")
        return url
    }
}

private actor FakeFolderSourceCreator: FolderSourceCreating {
    let source: FolderSource
    let trace: CreateGlassTrace

    init(source: FolderSource, trace: CreateGlassTrace) {
        self.source = source
        self.trace = trace
    }

    func createSource(for selectedURL: URL) async throws -> FolderSource {
        await trace.append("source")
        return source
    }
}

@MainActor
private final class FakePlacementProvider: InitialGlassPlacementProviding {
    let placement: GlassPlacement

    init(placement: GlassPlacement) {
        self.placement = placement
    }

    func initialPlacement() throws -> GlassPlacement {
        placement
    }
}

private actor FakeConfigurationStore: ConditionalConfigurationPersisting {
    let trace: CreateGlassTrace
    let loaded: [GlassConfiguration]
    let failLoad: Bool
    let failSave: Bool
    let rejectConditionalSave: Bool
    private var saved: [[GlassConfiguration]] = []

    init(
        trace: CreateGlassTrace,
        loaded: [GlassConfiguration] = [],
        failLoad: Bool = false,
        failSave: Bool = false,
        rejectConditionalSave: Bool = false
    ) {
        self.trace = trace
        self.loaded = loaded
        self.failLoad = failLoad
        self.failSave = failSave
        self.rejectConditionalSave = rejectConditionalSave
    }

    func load() async throws -> [GlassConfiguration] {
        await trace.append("load")
        if failLoad { throw CreateGlassTestError.injected }
        return loaded
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        await trace.append("save")
        if failSave { throw CreateGlassTestError.injected }
        saved.append(configurations)
    }

    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool {
        await trace.append("save")
        if failSave { throw CreateGlassTestError.injected }
        guard !rejectConditionalSave, expectedCurrent == loaded else {
            return false
        }
        saved.append(configurations)
        return true
    }

    func lastSaved() -> [GlassConfiguration]? {
        saved.last
    }
}

private actor FakeAccessController: FolderAccessControlling {
    let trace: CreateGlassTrace
    let refreshedSource: FolderSource?
    private var acquireCount = 0
    private var released: [UUID] = []

    init(trace: CreateGlassTrace, refreshedSource: FolderSource? = nil) {
        self.trace = trace
        self.refreshedSource = refreshedSource
    }

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        await trace.append("acquire")
        acquireCount += 1
        return FolderAccessAcquisition(
            handle: FolderAccessHandle(
                glassID: glassID,
                url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
            ),
            refreshedSource: refreshedSource
        )
    }

    func release(handleID: UUID) async {
        await trace.append("release")
        released.append(handleID)
    }

    func counts() -> (acquired: Int, released: Int) {
        (acquireCount, released.count)
    }
}

private actor FakeEventStreaming: FileEventStreaming {
    let trace: CreateGlassTrace
    let fail: Bool
    let subscriptionID = UUID()
    private var stopped: [UUID] = []

    init(trace: CreateGlassTrace, fail: Bool = false) {
        self.trace = trace
        self.fail = fail
    }

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        await trace.append("subscribe")
        if fail { throw CreateGlassTestError.injected }
        return FileEventSubscription(
            id: subscriptionID,
            events: AsyncStream { _ in }
        )
    }

    func stop(subscriptionID: UUID) async {
        await trace.append("stopEvents")
        stopped.append(subscriptionID)
    }

    func stopCount() -> Int {
        stopped.count
    }
}

private actor FakeSnapshotReader: FolderSnapshotReading {
    let trace: CreateGlassTrace
    let fail: Bool

    init(trace: CreateGlassTrace, fail: Bool = false) {
        self.trace = trace
        self.fail = fail
    }

    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        await trace.append("snapshot")
        if fail { throw CreateGlassTestError.injected }
        return FolderSnapshot(
            folderIdentity: FolderIdentity(
                resourceIdentifier: nil,
                standardizedURL: access.url
            ),
            items: [],
            isTruncated: false,
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            generation: generation
        )
    }
}

private func source(path: String, marker: UInt8) -> FolderSource {
    FolderSource(
        bookmarkData: Data([marker]),
        lastKnownPath: path,
        fingerprint: nil
    )
}

@MainActor
private func makeUseCase(
    selectedURL: URL?,
    trace: CreateGlassTrace,
    initialSource: FolderSource,
    refreshedSource: FolderSource? = nil,
    failLoad: Bool = false,
    failSave: Bool = false,
    rejectConditionalSave: Bool = false,
    failEvents: Bool = false,
    failSnapshot: Bool = false
) throws -> (
    useCase: CreateGlassUseCase,
    store: FakeConfigurationStore,
    access: FakeAccessController,
    events: FakeEventStreaming
) {
    let store = FakeConfigurationStore(
        trace: trace,
        failLoad: failLoad,
        failSave: failSave,
        rejectConditionalSave: rejectConditionalSave
    )
    let access = FakeAccessController(
        trace: trace,
        refreshedSource: refreshedSource
    )
    let events = FakeEventStreaming(trace: trace, fail: failEvents)
    let useCase = CreateGlassUseCase(
        folderSelector: FakeFolderSelector(url: selectedURL, trace: trace),
        sourceCreator: FakeFolderSourceCreator(source: initialSource, trace: trace),
        placementProvider: FakePlacementProvider(
            placement: try GlassPlacement(x: 100, y: 120)
        ),
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: FakeSnapshotReader(trace: trace, fail: failSnapshot)
    )
    return (useCase, store, access, events)
}

@Test
@MainActor
func createGlassStartsEventsBeforeSnapshotAndPersistsAfterSnapshot() async throws {
    let trace = CreateGlassTrace()
    let selected = URL(fileURLWithPath: "/tmp/Projects", isDirectory: true)
    let initialSource = source(path: selected.path, marker: 1)
    let refreshed = source(path: selected.path, marker: 2)
    let setup = try makeUseCase(
        selectedURL: selected,
        trace: trace,
        initialSource: initialSource,
        refreshedSource: refreshed
    )

    let result = try #require(try await setup.useCase.execute())
    let saved = try #require(await setup.store.lastSaved())

    #expect(result.configuration.title == "Projects")
    #expect(result.configuration.source == refreshed)
    #expect(result.snapshot.generation == 1)
    #expect(saved == [result.configuration])
    #expect(await trace.snapshot() == [
        "select", "source", "load", "acquire", "subscribe", "snapshot", "save",
    ])
    #expect(await setup.access.counts().released == 0)
    #expect(await setup.events.stopCount() == 0)
}

@Test
@MainActor
func cancelledFolderSelectionProducesNoSideEffects() async throws {
    let trace = CreateGlassTrace()
    let initialSource = source(path: "/tmp/unused", marker: 1)
    let setup = try makeUseCase(
        selectedURL: nil,
        trace: trace,
        initialSource: initialSource
    )

    let result = try await setup.useCase.execute()

    #expect(result == nil)
    #expect(await trace.snapshot() == ["select"])
    #expect(await setup.access.counts().acquired == 0)
}

@Test
@MainActor
func configurationLoadFailureOccursBeforeSecurityScopeAcquisition() async throws {
    let trace = CreateGlassTrace()
    let selected = URL(fileURLWithPath: "/tmp/LoadFailure", isDirectory: true)
    let setup = try makeUseCase(
        selectedURL: selected,
        trace: trace,
        initialSource: source(path: selected.path, marker: 1),
        failLoad: true
    )

    do {
        _ = try await setup.useCase.execute()
        Issue.record("Expected configuration load failure")
    } catch let error as CreateGlassError {
        #expect(error == .configurationLoadFailed)
    }

    #expect(await trace.snapshot() == ["select", "source", "load"])
    #expect(await setup.access.counts().acquired == 0)
}

@Test
@MainActor
func eventSubscriptionFailureReleasesSecurityScope() async throws {
    let trace = CreateGlassTrace()
    let selected = URL(fileURLWithPath: "/tmp/EventFailure", isDirectory: true)
    let setup = try makeUseCase(
        selectedURL: selected,
        trace: trace,
        initialSource: source(path: selected.path, marker: 1),
        failEvents: true
    )

    do {
        _ = try await setup.useCase.execute()
        Issue.record("Expected event subscription failure")
    } catch let error as CreateGlassError {
        #expect(error == .eventStreamFailed)
    }

    #expect(await trace.snapshot() == [
        "select", "source", "load", "acquire", "subscribe", "release",
    ])
    #expect(await setup.access.counts().released == 1)
    #expect(await setup.events.stopCount() == 0)
}

@Test
@MainActor
func snapshotFailureStopsWatcherThenReleasesSecurityScopeAndDoesNotSave() async throws {
    let trace = CreateGlassTrace()
    let selected = URL(fileURLWithPath: "/tmp/SnapshotFailure", isDirectory: true)
    let setup = try makeUseCase(
        selectedURL: selected,
        trace: trace,
        initialSource: source(path: selected.path, marker: 1),
        failSnapshot: true
    )

    do {
        _ = try await setup.useCase.execute()
        Issue.record("Expected snapshot failure")
    } catch let error as CreateGlassError {
        #expect(error == .snapshotFailed)
    }

    #expect(await trace.snapshot() == [
        "select", "source", "load", "acquire", "subscribe", "snapshot", "stopEvents", "release",
    ])
    #expect(await setup.events.stopCount() == 1)
    #expect(await setup.access.counts().released == 1)
    #expect(await setup.store.lastSaved() == nil)
}

@Test
@MainActor
func staleConfigurationStopsWatcherThenReleasesSecurityScopeWithoutSaving() async throws {
    let trace = CreateGlassTrace()
    let selected = URL(fileURLWithPath: "/tmp/StaleConfiguration", isDirectory: true)
    let setup = try makeUseCase(
        selectedURL: selected,
        trace: trace,
        initialSource: source(path: selected.path, marker: 1),
        rejectConditionalSave: true
    )

    do {
        _ = try await setup.useCase.execute()
        Issue.record("Expected configuration save failure")
    } catch let error as CreateGlassError {
        #expect(error == .configurationSaveFailed)
    }

    #expect(await trace.snapshot() == [
        "select", "source", "load", "acquire", "subscribe", "snapshot", "save", "stopEvents", "release",
    ])
    #expect(await setup.store.lastSaved() == nil)
    #expect(await setup.events.stopCount() == 1)
    #expect(await setup.access.counts().released == 1)
}

@Test
@MainActor
func persistenceFailureStopsWatcherThenReleasesSecurityScopeAfterSnapshot() async throws {
    let trace = CreateGlassTrace()
    let selected = URL(fileURLWithPath: "/tmp/SaveFailure", isDirectory: true)
    let setup = try makeUseCase(
        selectedURL: selected,
        trace: trace,
        initialSource: source(path: selected.path, marker: 1),
        failSave: true
    )

    do {
        _ = try await setup.useCase.execute()
        Issue.record("Expected configuration save failure")
    } catch let error as CreateGlassError {
        #expect(error == .configurationSaveFailed)
    }

    #expect(await trace.snapshot() == [
        "select", "source", "load", "acquire", "subscribe", "snapshot", "save", "stopEvents", "release",
    ])
    #expect(await setup.events.stopCount() == 1)
    #expect(await setup.access.counts().released == 1)
}
