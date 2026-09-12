import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor ReconnectIdentityRecordStore: PendingCopyRecording {
    private let record: PendingCopyRecord

    init(record: PendingCopyRecord) {
        self.record = record
    }

    func records() async throws -> [PendingCopyRecord] {
        [record]
    }

    func upsert(_ record: PendingCopyRecord) async throws {
        _ = record
    }

    func remove(operationID: UUID) async throws {
        _ = operationID
    }
}

private actor ReconnectIdentityConfigurationStore: ConditionalConfigurationPersisting {
    private var values: [GlassConfiguration]
    private var saves: [[GlassConfiguration]] = []

    init(configuration: GlassConfiguration) {
        self.values = [configuration]
    }

    func load() async throws -> [GlassConfiguration] {
        values
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        saves.append(configurations)
        values = configurations
    }

    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool {
        guard values == expectedCurrent else {
            return false
        }
        saves.append(configurations)
        values = configurations
        return true
    }

    func savedValues() -> [[GlassConfiguration]] {
        saves
    }
}

@MainActor
private final class ReconnectIdentityFolderSelector: FolderSelecting {
    private let selectedURL: URL

    init(selectedURL: URL) {
        self.selectedURL = selectedURL
    }

    func selectFolder() async -> URL? {
        selectedURL
    }
}

private actor ReconnectIdentitySourceCreator: FolderSourceCreating {
    private let source: FolderSource

    init(source: FolderSource) {
        self.source = source
    }

    func createSource(for selectedURL: URL) async throws -> FolderSource {
        _ = selectedURL
        return source
    }
}

private actor ReconnectIdentityAccessController: FolderAccessControlling {
    private let refreshedSource: FolderSource?
    private var acquireCounter = 0
    private var releaseCounter = 0

    init(refreshedSource: FolderSource? = nil) {
        self.refreshedSource = refreshedSource
    }

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        acquireCounter += 1
        return FolderAccessAcquisition(
            handle: FolderAccessHandle(
                glassID: glassID,
                url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
            ),
            refreshedSource: refreshedSource
        )
    }

    func release(handleID: UUID) async {
        _ = handleID
        releaseCounter += 1
    }

    func acquireCount() -> Int {
        acquireCounter
    }

    func releaseCount() -> Int {
        releaseCounter
    }
}

private func reconnectPersistentIdentity(
    volume: String? = "volume-uuid-A",
    document: Int? = 41
) -> PersistentFolderIdentity {
    PersistentFolderIdentity(
        volumeUUIDString: volume,
        documentIdentifier: document
    )
}

private func reconnectIdentitySource(
    bookmark: UInt8,
    path: String,
    persistentIdentity: PersistentFolderIdentity?
) -> FolderSource {
    FolderSource(
        bookmarkData: Data([bookmark]),
        lastKnownPath: path,
        persistentIdentity: persistentIdentity
    )
}

private func reconnectIdentityConfiguration(
    glassID: GlassID,
    persistentIdentity: PersistentFolderIdentity?
) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: glassID,
        title: "Documents",
        source: reconnectIdentitySource(
            bookmark: 1,
            path: "/old/Documents",
            persistentIdentity: persistentIdentity
        ),
        placement: GlassPlacement(x: 10, y: 20),
        showOnAllSpaces: false,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func reconnectIdentityRecord(glassID: GlassID) -> PendingCopyRecord {
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
private func reconnectIdentityUseCase(
    record: PendingCopyRecord,
    configurationStore: ReconnectIdentityConfigurationStore,
    selectedSource: FolderSource,
    accessController: ReconnectIdentityAccessController
) -> PendingCopyDestinationReconnectUseCase {
    PendingCopyDestinationReconnectUseCase(
        pendingCopyStore: ReconnectIdentityRecordStore(record: record),
        configurationStore: configurationStore,
        folderSelector: ReconnectIdentityFolderSelector(
            selectedURL: URL(fileURLWithPath: selectedSource.lastKnownPath, isDirectory: true)
        ),
        sourceCreator: ReconnectIdentitySourceCreator(source: selectedSource),
        accessController: accessController,
        activityGate: FileOperationActivityGate()
    )
}

@Test
@MainActor
func reconnectPersistsRefreshedSourceReturnedByValidatedAccess() async throws {
    let glassID = GlassID()
    let identity = reconnectPersistentIdentity()
    let original = try reconnectIdentityConfiguration(
        glassID: glassID,
        persistentIdentity: identity
    )
    let selected = reconnectIdentitySource(
        bookmark: 9,
        path: "/new/Documents",
        persistentIdentity: identity
    )
    let refreshed = reconnectIdentitySource(
        bookmark: 10,
        path: "/resolved/Documents",
        persistentIdentity: identity
    )
    let record = reconnectIdentityRecord(glassID: glassID)
    let store = ReconnectIdentityConfigurationStore(configuration: original)
    let access = ReconnectIdentityAccessController(refreshedSource: refreshed)
    let useCase = reconnectIdentityUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        accessController: access
    )

    #expect(try await useCase.execute(operationID: record.operationID))

    let saves = await store.savedValues()
    #expect(saves.count == 1)
    #expect(saves[0].count == 1)
    #expect(saves[0][0].source == refreshed)
    #expect(saves[0][0].source != selected)
    #expect(await access.acquireCount() == 1)
    #expect(await access.releaseCount() == 1)
}

@Test
@MainActor
func reconnectRejectsVolumeOnlyPersistentIdentityBeforeAccessOrSave() async throws {
    let glassID = GlassID()
    let volumeOnly = reconnectPersistentIdentity(document: nil)
    let original = try reconnectIdentityConfiguration(
        glassID: glassID,
        persistentIdentity: volumeOnly
    )
    let selected = reconnectIdentitySource(
        bookmark: 9,
        path: "/new/Documents",
        persistentIdentity: volumeOnly
    )
    let record = reconnectIdentityRecord(glassID: glassID)
    let store = ReconnectIdentityConfigurationStore(configuration: original)
    let access = ReconnectIdentityAccessController()
    let useCase = reconnectIdentityUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        accessController: access
    )

    do {
        _ = try await useCase.execute(operationID: record.operationID)
        Issue.record("Expected directory identity proof to be unavailable")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .selectedDestinationIdentityUnavailable)
    }

    #expect(await access.acquireCount() == 0)
    #expect(await access.releaseCount() == 0)
    #expect(await store.savedValues().isEmpty)
}

@Test
@MainActor
func reconnectRejectsAccessTimePersistentIdentityChangeAndReleasesAccess() async throws {
    let glassID = GlassID()
    let expectedIdentity = reconnectPersistentIdentity(document: 41)
    let original = try reconnectIdentityConfiguration(
        glassID: glassID,
        persistentIdentity: expectedIdentity
    )
    let selected = reconnectIdentitySource(
        bookmark: 9,
        path: "/new/Documents",
        persistentIdentity: expectedIdentity
    )
    let replacement = reconnectIdentitySource(
        bookmark: 10,
        path: "/resolved/Documents",
        persistentIdentity: reconnectPersistentIdentity(document: 99)
    )
    let record = reconnectIdentityRecord(glassID: glassID)
    let store = ReconnectIdentityConfigurationStore(configuration: original)
    let access = ReconnectIdentityAccessController(refreshedSource: replacement)
    let useCase = reconnectIdentityUseCase(
        record: record,
        configurationStore: store,
        selectedSource: selected,
        accessController: access
    )

    do {
        _ = try await useCase.execute(operationID: record.operationID)
        Issue.record("Expected access-time destination identity mismatch")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .selectedDestinationMismatch)
    }

    #expect(await access.acquireCount() == 1)
    #expect(await access.releaseCount() == 1)
    #expect(await store.savedValues().isEmpty)
}
