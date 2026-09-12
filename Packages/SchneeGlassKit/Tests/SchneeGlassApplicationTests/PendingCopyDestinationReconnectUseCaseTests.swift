import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum ReconnectTestError: Error, Sendable { case injected }

private actor ReconnectRecordStore: PendingCopyRecording {
    private var values: [PendingCopyRecord]

    init(records: [PendingCopyRecord]) { self.values = records }

    func records() async throws -> [PendingCopyRecord] { values }
    func upsert(_ record: PendingCopyRecord) async throws {
        values.removeAll { $0.operationID == record.operationID }
        values.append(record)
    }
    func remove(operationID: UUID) async throws {
        values.removeAll { $0.operationID == operationID }
    }
}

private actor ReconnectConfigurationStore: ConditionalConfigurationPersisting {
    private var values: [GlassConfiguration]
    private var saves: [[GlassConfiguration]] = []
    private let rejectConditionalSave: Bool

    init(
        configurations: [GlassConfiguration],
        rejectConditionalSave: Bool = false
    ) {
        self.values = configurations
        self.rejectConditionalSave = rejectConditionalSave
    }

    func load() async throws -> [GlassConfiguration] { values }
    func save(_ configurations: [GlassConfiguration]) async throws {
        saves.append(configurations)
        values = configurations
    }

    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool {
        guard !rejectConditionalSave, values == expectedCurrent else {
            return false
        }
        saves.append(configurations)
        values = configurations
        return true
    }

    func replaceForTest(_ configurations: [GlassConfiguration]) {
        values = configurations
    }

    func savedValues() -> [[GlassConfiguration]] { saves }
}

@MainActor
private final class ReconnectFolderSelector: FolderSelecting {
    private let selectedURL: URL?

    init(selectedURL: URL?) {
        self.selectedURL = selectedURL
    }

    func selectFolder() async -> URL? { selectedURL }
}

private actor ReconnectSourceCreator: FolderSourceCreating {
    private let source: FolderSource
    private let onCreate: (@Sendable () async -> Void)?

    init(
        source: FolderSource,
        onCreate: (@Sendable () async -> Void)? = nil
    ) {
        self.source = source
        self.onCreate = onCreate
    }

    func createSource(for selectedURL: URL) async throws -> FolderSource {
        if let onCreate { await onCreate() }
        return source
    }
}

private actor ReconnectAccessController: FolderAccessControlling {
    private let shouldFail: Bool
    private var acquires = 0
    private var releases = 0

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func acquire(source: FolderSource, glassID: GlassID) async throws -> FolderAccessAcquisition {
        if shouldFail { throw ReconnectTestError.injected }
        acquires += 1
        return FolderAccessAcquisition(
            handle: FolderAccessHandle(
                glassID: glassID,
                url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
            )
        )
    }

    func release(handleID: UUID) async { releases += 1 }
    func acquireCount() -> Int { acquires }
    func releaseCount() -> Int { releases }
}

private func reconnectPersistentIdentity(
    volume: String = "volume-uuid-A",
    document: Int = 101
) -> PersistentFolderIdentity {
    PersistentFolderIdentity(
        volumeUUIDString: volume,
        documentIdentifier: document
    )
}

private func reconnectConfiguration(
    glassID: GlassID,
    persistentIdentity: PersistentFolderIdentity? = reconnectPersistentIdentity(),
    title: String = "Documents"
) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: glassID,
        title: title,
        source: FolderSource(
            bookmarkData: Data([1]),
            lastKnownPath: "/old/Documents",
            persistentIdentity: persistentIdentity
        ),
        placement: GlassPlacement(x: 12, y: 34),
        showOnAllSpaces: true,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func reconnectSource(
    bookmark: Data,
    path: String,
    persistentIdentity: PersistentFolderIdentity = reconnectPersistentIdentity()
) -> FolderSource {
    FolderSource(
        bookmarkData: bookmark,
        lastKnownPath: path,
        persistentIdentity: persistentIdentity
    )
}

private func reconnectRecord(glassID: GlassID) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "report.txt",
        expectedSize: 7,
        stagingResourceIdentifier: "staging-identity",
        state: .staging
    )
}

@MainActor
private func reconnectUseCase(
    record: PendingCopyRecord,
    configurationStore: ReconnectConfigurationStore,
    selectedSource: FolderSource,
    selectedURL: URL? = URL(fileURLWithPath: "/new/Documents", isDirectory: true),
    access: ReconnectAccessController = ReconnectAccessController(),
    gate: FileOperationActivityGate = FileOperationActivityGate(),
    onCreate: (@Sendable () async -> Void)? = nil
) -> PendingCopyDestinationReconnectUseCase {
    PendingCopyDestinationReconnectUseCase(
        pendingCopyStore: ReconnectRecordStore(records: [record]),
        configurationStore: configurationStore,
        folderSelector: ReconnectFolderSelector(selectedURL: selectedURL),
        sourceCreator: ReconnectSourceCreator(source: selectedSource, onCreate: onCreate),
        accessController: access,
        activityGate: gate
    )
}

@Test
@MainActor
func reconnectCancelDoesNotAcquireLeaseOrSave() async throws {
    let glassID = GlassID()
    let record = reconnectRecord(glassID: glassID)
    let configuration = try reconnectConfiguration(glassID: glassID)
    let store = ReconnectConfigurationStore(configurations: [configuration])
    let useCase = reconnectUseCase(
        record: record,
        configurationStore: store,
        selectedSource: configuration.source,
        selectedURL: nil
    )

    #expect(try await useCase.execute(operationID: record.operationID) == false)
    #expect(await store.savedValues().isEmpty)
}

@Test
@MainActor
func reconnectMatchingPersistentIdentityPersistsOnlyNewSourceAndValidatesAccess() async throws {
    let glassID = GlassID()
    let record = reconnectRecord(glassID: glassID)
    let original = try reconnectConfiguration(glassID: glassID)
    let selected = reconnectSource(
        bookmark: Data([9, 9]),
        path: "/new/Documents"
    )
    let store = ReconnectConfigurationStore(configurations: [original])
    let access = ReconnectAccessController()
    let useCase = reconnectUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        access: access
    )

    #expect(try await useCase.execute(operationID: record.operationID))

    let saves = await store.savedValues()
    #expect(saves.count == 1)
    #expect(saves[0].count == 1)
    #expect(saves[0][0].source == selected)
    #expect(saves[0][0].id == original.id)
    #expect(saves[0][0].title == original.title)
    #expect(saves[0][0].placement == original.placement)
    #expect(saves[0][0].showOnAllSpaces == original.showOnAllSpaces)
    #expect(saves[0][0].createdAt == original.createdAt)
    #expect(await access.acquireCount() == 1)
    #expect(await access.releaseCount() == 1)
}

@Test
@MainActor
func reconnectRejectsPersistentIdentityMismatchBeforeAccessOrSave() async throws {
    let glassID = GlassID()
    let record = reconnectRecord(glassID: glassID)
    let original = try reconnectConfiguration(glassID: glassID)
    let selected = reconnectSource(
        bookmark: Data([2]),
        path: "/wrong",
        persistentIdentity: reconnectPersistentIdentity(document: 999)
    )
    let store = ReconnectConfigurationStore(configurations: [original])
    let access = ReconnectAccessController()
    let useCase = reconnectUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        access: access
    )

    do {
        _ = try await useCase.execute(operationID: record.operationID)
        Issue.record("Expected selectedDestinationMismatch")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .selectedDestinationMismatch)
    }

    #expect(await access.acquireCount() == 0)
    #expect(await store.savedValues().isEmpty)
}

@Test
@MainActor
func reconnectRejectsConfigurationChangedWhilePickerWasOpen() async throws {
    let glassID = GlassID()
    let record = reconnectRecord(glassID: glassID)
    let original = try reconnectConfiguration(glassID: glassID)
    let changed = try reconnectConfiguration(glassID: glassID, title: "Changed")
    let selected = reconnectSource(bookmark: Data([3]), path: "/new/Documents")
    let store = ReconnectConfigurationStore(configurations: [original])
    let useCase = reconnectUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        onCreate: {
            await store.replaceForTest([changed])
        }
    )

    do {
        _ = try await useCase.execute(operationID: record.operationID)
        Issue.record("Expected staleRecoveryState")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .staleRecoveryState)
    }

    #expect(await store.savedValues().isEmpty)
}

@Test
@MainActor
func reconnectRejectsConfigurationChangedAfterFinalRead() async throws {
    let glassID = GlassID()
    let record = reconnectRecord(glassID: glassID)
    let original = try reconnectConfiguration(glassID: glassID)
    let selected = reconnectSource(bookmark: Data([8]), path: "/new/Documents")
    let store = ReconnectConfigurationStore(
        configurations: [original],
        rejectConditionalSave: true
    )
    let access = ReconnectAccessController()
    let gate = FileOperationActivityGate()
    let useCase = reconnectUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        access: access,
        gate: gate
    )

    do {
        _ = try await useCase.execute(operationID: record.operationID)
        Issue.record("Expected staleRecoveryState")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .staleRecoveryState)
    }

    #expect(await store.savedValues().isEmpty)
    #expect(await access.acquireCount() == 1)
    #expect(await access.releaseCount() == 1)
    #expect(!(await gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func reconnectRejectsWhileCopyActiveWithoutConfigurationWrite() async throws {
    let glassID = GlassID()
    let record = reconnectRecord(glassID: glassID)
    let original = try reconnectConfiguration(glassID: glassID)
    let selected = reconnectSource(bookmark: Data([4]), path: "/new/Documents")
    let store = ReconnectConfigurationStore(configurations: [original])
    let gate = FileOperationActivityGate()
    #expect(await gate.beginCopy())
    let useCase = reconnectUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        gate: gate
    )

    do {
        _ = try await useCase.execute(operationID: record.operationID)
        Issue.record("Expected copyInProgress")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .copyInProgress)
    }

    #expect(await store.savedValues().isEmpty)
    await gate.endCopy()
}

@Test
@MainActor
func reconnectAccessFailureReleasesRecoveryLeaseAndDoesNotSave() async throws {
    let glassID = GlassID()
    let record = reconnectRecord(glassID: glassID)
    let original = try reconnectConfiguration(glassID: glassID)
    let selected = reconnectSource(bookmark: Data([5]), path: "/new/Documents")
    let store = ReconnectConfigurationStore(configurations: [original])
    let gate = FileOperationActivityGate()
    let useCase = reconnectUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        access: ReconnectAccessController(shouldFail: true),
        gate: gate
    )

    do {
        _ = try await useCase.execute(operationID: record.operationID)
        Issue.record("Expected selectedDestinationAccessFailed")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .selectedDestinationAccessFailed)
    }

    #expect(await store.savedValues().isEmpty)
    #expect(!(await gate.hasActiveRecoveryMutation()))
    #expect(await gate.beginCopy())
    await gate.endCopy()
}
