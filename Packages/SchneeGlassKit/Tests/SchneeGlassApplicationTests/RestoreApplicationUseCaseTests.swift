import FileDomain
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RestoreTestError: Error, Sendable {
    case injected
}

private actor RestoreTrace {
    private var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }

    func snapshot() -> [String] {
        values
    }
}

private actor RestoreConfigurationStore: ConfigurationPersisting {
    let configurations: [GlassConfiguration]
    let trace: RestoreTrace
    let failLoad: Bool
    let failSave: Bool
    private var saves: [[GlassConfiguration]] = []

    init(
        configurations: [GlassConfiguration],
        trace: RestoreTrace,
        failLoad: Bool = false,
        failSave: Bool = false
    ) {
        self.configurations = configurations
        self.trace = trace
        self.failLoad = failLoad
        self.failSave = failSave
    }

    func load() async throws -> [GlassConfiguration] {
        await trace.append("load")
        if failLoad { throw RestoreTestError.injected }
        return configurations
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        await trace.append("save")
        if failSave { throw RestoreTestError.injected }
        saves.append(configurations)
    }

    func lastSaved() -> [GlassConfiguration]? {
        saves.last
    }
}

private actor RestoreAccessController: FolderAccessControlling {
    let trace: RestoreTrace
    let failures: Set<GlassID>
    let refreshedSources: [GlassID: FolderSource]
    private var released: [UUID] = []

    init(
        trace: RestoreTrace,
        failures: Set<GlassID> = [],
        refreshedSources: [GlassID: FolderSource] = [:]
    ) {
        self.trace = trace
        self.failures = failures
        self.refreshedSources = refreshedSources
    }

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        await trace.append("acquire:\(glassID.rawValue.uuidString)")
        if failures.contains(glassID) {
            throw FolderAccessError.accessDenied
        }
        return FolderAccessAcquisition(
            handle: FolderAccessHandle(
                glassID: glassID,
                url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
            ),
            refreshedSource: refreshedSources[glassID]
        )
    }

    func release(handleID: UUID) async {
        await trace.append("release")
        released.append(handleID)
    }

    func releaseCount() -> Int {
        released.count
    }
}

private actor RestoreEventStreaming: FileEventStreaming {
    let trace: RestoreTrace
    let failFor: Set<GlassID>
    private var stopped: [UUID] = []

    init(trace: RestoreTrace, failFor: Set<GlassID> = []) {
        self.trace = trace
        self.failFor = failFor
    }

    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription {
        await trace.append("subscribe:\(access.glassID.rawValue.uuidString)")
        if failFor.contains(access.glassID) {
            throw RestoreTestError.injected
        }
        return FileEventSubscription(
            events: AsyncStream { _ in }
        )
    }

    func stop(subscriptionID: UUID) async {
        await trace.append("stop")
        stopped.append(subscriptionID)
    }

    func stopCount() -> Int {
        stopped.count
    }
}

private actor RestoreSnapshotReader: FolderSnapshotReading {
    let trace: RestoreTrace
    let failFor: Set<GlassID>

    init(trace: RestoreTrace, failFor: Set<GlassID> = []) {
        self.trace = trace
        self.failFor = failFor
    }

    func snapshot(
        for access: FolderAccessHandle,
        generation: UInt64
    ) async throws -> FolderSnapshot {
        await trace.append("snapshot:\(access.glassID.rawValue.uuidString)")
        if failFor.contains(access.glassID) {
            throw RestoreTestError.injected
        }
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

private func restoreConfiguration(
    title: String,
    marker: UInt8,
    id: GlassID = GlassID()
) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: id,
        title: title,
        source: FolderSource(
            bookmarkData: Data([marker]),
            lastKnownPath: "/tmp/\(title)"
        ),
        placement: GlassPlacement(x: 100, y: 100),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Test
func emptyConfigurationRestoresNothingWithoutOpeningResources() async throws {
    let trace = RestoreTrace()
    let store = RestoreConfigurationStore(configurations: [], trace: trace)
    let access = RestoreAccessController(trace: trace)
    let events = RestoreEventStreaming(trace: trace)
    let reader = RestoreSnapshotReader(trace: trace)
    let useCase = RestoreApplicationUseCase(
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: reader
    )

    let result = try await useCase.execute()

    #expect(result.seeds.isEmpty)
    #expect(result.failures.isEmpty)
    #expect(result.refreshedConfigurationSavePending == false)
    #expect(await trace.snapshot() == ["load"])
}

@Test
func oneBrokenGlassDoesNotPreventAnotherFromRestoring() async throws {
    let trace = RestoreTrace()
    let broken = try restoreConfiguration(title: "Broken", marker: 1)
    let healthy = try restoreConfiguration(title: "Healthy", marker: 2)
    let store = RestoreConfigurationStore(configurations: [broken, healthy], trace: trace)
    let access = RestoreAccessController(trace: trace, failures: [broken.id])
    let events = RestoreEventStreaming(trace: trace)
    let reader = RestoreSnapshotReader(trace: trace)
    let useCase = RestoreApplicationUseCase(
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: reader
    )

    let result = try await useCase.execute()

    #expect(result.seeds.map(\.configuration.id) == [healthy.id])
    #expect(result.failures.count == 1)
    #expect(result.failures.first?.glassID == broken.id)
    #expect(result.failures.first?.reason == .folderAccess(.accessDenied))
}

@Test
func eventSubscriptionFailureReleasesAcquiredSecurityScope() async throws {
    let trace = RestoreTrace()
    let configuration = try restoreConfiguration(title: "EventsFail", marker: 1)
    let store = RestoreConfigurationStore(configurations: [configuration], trace: trace)
    let access = RestoreAccessController(trace: trace)
    let events = RestoreEventStreaming(trace: trace, failFor: [configuration.id])
    let reader = RestoreSnapshotReader(trace: trace)
    let useCase = RestoreApplicationUseCase(
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: reader
    )

    let result = try await useCase.execute()

    #expect(result.seeds.isEmpty)
    #expect(result.failures.first?.reason == .eventStreamFailed)
    #expect(await access.releaseCount() == 1)
    #expect(await events.stopCount() == 0)
}

@Test
func snapshotFailureStopsSubscriptionBeforeReleasingAccess() async throws {
    let trace = RestoreTrace()
    let configuration = try restoreConfiguration(title: "SnapshotFail", marker: 1)
    let store = RestoreConfigurationStore(configurations: [configuration], trace: trace)
    let access = RestoreAccessController(trace: trace)
    let events = RestoreEventStreaming(trace: trace)
    let reader = RestoreSnapshotReader(trace: trace, failFor: [configuration.id])
    let useCase = RestoreApplicationUseCase(
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: reader
    )

    let result = try await useCase.execute()
    let recorded = await trace.snapshot()

    #expect(result.seeds.isEmpty)
    #expect(result.failures.first?.reason == .snapshotFailed)
    let stopIndex = try #require(recorded.firstIndex(of: "stop"))
    let releaseIndex = try #require(recorded.firstIndex(of: "release"))
    #expect(stopIndex < releaseIndex)
}

@Test
func refreshedBookmarkIsPersistedAfterSuccessfulRestore() async throws {
    let trace = RestoreTrace()
    let configuration = try restoreConfiguration(title: "Stale", marker: 1)
    let refreshed = FolderSource(
        bookmarkData: Data([9]),
        lastKnownPath: configuration.source.lastKnownPath,
        fingerprint: nil
    )
    let store = RestoreConfigurationStore(configurations: [configuration], trace: trace)
    let access = RestoreAccessController(
        trace: trace,
        refreshedSources: [configuration.id: refreshed]
    )
    let events = RestoreEventStreaming(trace: trace)
    let reader = RestoreSnapshotReader(trace: trace)
    let useCase = RestoreApplicationUseCase(
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: reader
    )

    let result = try await useCase.execute()
    let saved = try #require(await store.lastSaved())

    #expect(result.seeds.first?.configuration.source == refreshed)
    #expect(saved.first?.source == refreshed)
    #expect(result.refreshedConfigurationSavePending == false)
}

@Test
func refreshedBookmarkSaveFailureKeepsLiveSeedAndReportsPendingSave() async throws {
    let trace = RestoreTrace()
    let configuration = try restoreConfiguration(title: "SavePending", marker: 1)
    let refreshed = FolderSource(
        bookmarkData: Data([9]),
        lastKnownPath: configuration.source.lastKnownPath,
        fingerprint: nil
    )
    let store = RestoreConfigurationStore(
        configurations: [configuration],
        trace: trace,
        failSave: true
    )
    let access = RestoreAccessController(
        trace: trace,
        refreshedSources: [configuration.id: refreshed]
    )
    let events = RestoreEventStreaming(trace: trace)
    let reader = RestoreSnapshotReader(trace: trace)
    let useCase = RestoreApplicationUseCase(
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: reader
    )

    let result = try await useCase.execute()

    #expect(result.seeds.count == 1)
    #expect(result.refreshedConfigurationSavePending)
    #expect(await access.releaseCount() == 0)
    #expect(await events.stopCount() == 0)
}

@Test
func configurationLoadFailureIsGlobalAndOpensNoResources() async throws {
    let trace = RestoreTrace()
    let store = RestoreConfigurationStore(
        configurations: [],
        trace: trace,
        failLoad: true
    )
    let access = RestoreAccessController(trace: trace)
    let events = RestoreEventStreaming(trace: trace)
    let reader = RestoreSnapshotReader(trace: trace)
    let useCase = RestoreApplicationUseCase(
        configurationStore: store,
        accessController: access,
        eventStreaming: events,
        snapshotReader: reader
    )

    do {
        _ = try await useCase.execute()
        Issue.record("Expected configuration load failure")
    } catch let error as RestoreApplicationError {
        #expect(error == .configurationLoadFailed)
    }

    #expect(await trace.snapshot() == ["load"])
    #expect(await access.releaseCount() == 0)
}
