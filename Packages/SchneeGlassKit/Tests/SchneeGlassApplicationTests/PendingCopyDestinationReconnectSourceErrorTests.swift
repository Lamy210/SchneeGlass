import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private actor ReconnectSourceErrorRecordStore: PendingCopyRecording {
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

private actor ReconnectSourceErrorConfigurationStore: ConditionalConfigurationPersisting {
    private let configuration: GlassConfiguration
    private var saveCountValue = 0

    init(configuration: GlassConfiguration) {
        self.configuration = configuration
    }

    func load() async throws -> [GlassConfiguration] {
        [configuration]
    }

    func save(_ configurations: [GlassConfiguration]) async throws {
        _ = configurations
        saveCountValue += 1
    }

    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool {
        _ = configurations
        _ = expectedCurrent
        saveCountValue += 1
        return true
    }

    func saveCount() -> Int {
        saveCountValue
    }
}

@MainActor
private final class ReconnectSourceErrorFolderSelector: FolderSelecting {
    private let selectedURL: URL

    init(selectedURL: URL) {
        self.selectedURL = selectedURL
    }

    func selectFolder() async -> URL? {
        selectedURL
    }
}

private enum ReconnectSourceErrorFailure: Sendable {
    case bookmarkCreation
    case resourceIdentityUnavailable
    case unexpected
}

private enum ReconnectSourceErrorInjectedError: Error, Sendable {
    case injected
}

private struct ReconnectSourceErrorCreator: FolderSourceCreating {
    let failure: ReconnectSourceErrorFailure

    func createSource(for selectedURL: URL) async throws -> FolderSource {
        _ = selectedURL
        switch failure {
        case .bookmarkCreation:
            throw FolderSourceCreationError.bookmarkCreationFailed
        case .resourceIdentityUnavailable:
            throw FolderSourceCreationError.resourceIdentityUnavailable
        case .unexpected:
            throw ReconnectSourceErrorInjectedError.injected
        }
    }
}

private actor ReconnectSourceErrorAccessController: FolderAccessControlling {
    private var acquireCountValue = 0

    func acquire(
        source: FolderSource,
        glassID: GlassID
    ) async throws -> FolderAccessAcquisition {
        _ = source
        _ = glassID
        acquireCountValue += 1
        throw ReconnectSourceErrorInjectedError.injected
    }

    func release(handleID: UUID) async {
        _ = handleID
    }

    func acquireCount() -> Int {
        acquireCountValue
    }
}

private struct ReconnectSourceErrorFixture {
    let record: PendingCopyRecord
    let store: ReconnectSourceErrorConfigurationStore
    let access: ReconnectSourceErrorAccessController
    let gate: FileOperationActivityGate
    let useCase: PendingCopyDestinationReconnectUseCase
}

@MainActor
private func makeReconnectSourceErrorFixture(
    failure: ReconnectSourceErrorFailure
) throws -> ReconnectSourceErrorFixture {
    let glassID = GlassID()
    let fingerprint = ResourceFingerprint(
        volumeIdentifier: "volume-A",
        resourceIdentifier: "folder-A"
    )
    let configuration = try GlassConfiguration(
        id: glassID,
        title: "Documents",
        source: FolderSource(
            bookmarkData: Data([1]),
            lastKnownPath: "/old/Documents",
            fingerprint: fingerprint
        ),
        placement: GlassPlacement(x: 20, y: 30),
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let operationID = UUID()
    let record = PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "document.txt",
        expectedSize: 10,
        stagingResourceIdentifier: "staging-identity",
        state: .staging
    )
    let store = ReconnectSourceErrorConfigurationStore(configuration: configuration)
    let access = ReconnectSourceErrorAccessController()
    let gate = FileOperationActivityGate()
    let useCase = PendingCopyDestinationReconnectUseCase(
        pendingCopyStore: ReconnectSourceErrorRecordStore(record: record),
        configurationStore: store,
        folderSelector: ReconnectSourceErrorFolderSelector(
            selectedURL: URL(fileURLWithPath: "/selected/Documents", isDirectory: true)
        ),
        sourceCreator: ReconnectSourceErrorCreator(failure: failure),
        accessController: access,
        activityGate: gate
    )

    return ReconnectSourceErrorFixture(
        record: record,
        store: store,
        access: access,
        gate: gate,
        useCase: useCase
    )
}

@Test
@MainActor
func reconnectMapsSourceIdentityObservationFailureToIdentityUnavailable() async throws {
    let fixture = try makeReconnectSourceErrorFixture(failure: .resourceIdentityUnavailable)

    do {
        _ = try await fixture.useCase.execute(operationID: fixture.record.operationID)
        Issue.record("Expected selectedDestinationIdentityUnavailable")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .selectedDestinationIdentityUnavailable)
    }

    #expect(await fixture.store.saveCount() == 0)
    #expect(await fixture.access.acquireCount() == 0)
    #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func reconnectKeepsBookmarkCreationFailureAsSourceCreationFailed() async throws {
    let fixture = try makeReconnectSourceErrorFixture(failure: .bookmarkCreation)

    do {
        _ = try await fixture.useCase.execute(operationID: fixture.record.operationID)
        Issue.record("Expected sourceCreationFailed")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .sourceCreationFailed)
    }

    #expect(await fixture.store.saveCount() == 0)
    #expect(await fixture.access.acquireCount() == 0)
    #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}

@Test
@MainActor
func reconnectKeepsUnknownSourceCreatorFailureAsSourceCreationFailed() async throws {
    let fixture = try makeReconnectSourceErrorFixture(failure: .unexpected)

    do {
        _ = try await fixture.useCase.execute(operationID: fixture.record.operationID)
        Issue.record("Expected sourceCreationFailed")
    } catch let error as PendingCopyDestinationReconnectError {
        #expect(error == .sourceCreationFailed)
    }

    #expect(await fixture.store.saveCount() == 0)
    #expect(await fixture.access.acquireCount() == 0)
    #expect(!(await fixture.gate.hasActiveRecoveryMutation()))
}
