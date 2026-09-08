import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RecoveryCenterTestError: Error, Sendable {
    case injected
}

private actor RecoveryCenterStore: PendingCopyRecording {
    private var values: [PendingCopyRecord]
    private let failRecords: Bool
    private var removedIDs: [UUID] = []

    init(records: [PendingCopyRecord], failRecords: Bool = false) {
        self.values = records
        self.failRecords = failRecords
    }

    func records() async throws -> [PendingCopyRecord] {
        if failRecords { throw RecoveryCenterTestError.injected }
        return values
    }

    func upsert(_ record: PendingCopyRecord) async throws {
        values.removeAll { $0.operationID == record.operationID }
        values.append(record)
    }

    func remove(operationID: UUID) async throws {
        removedIDs.append(operationID)
        values.removeAll { $0.operationID == operationID }
    }

    func removals() -> [UUID] { removedIDs }
}

private actor RecoveryCenterConfigurationStore: ConfigurationPersisting {
    private let configurations: [GlassConfiguration]
    private let failLoad: Bool

    init(configurations: [GlassConfiguration], failLoad: Bool = false) {
        self.configurations = configurations
        self.failLoad = failLoad
    }

    func load() async throws -> [GlassConfiguration] {
        if failLoad { throw RecoveryCenterTestError.injected }
        return configurations
    }

    func save(_ configurations: [GlassConfiguration]) async throws {}
}

private actor RecoveryCenterAccessController: FolderAccessControlling {
    private let shouldFail: Bool
    private var acquiredGlassIDs: [GlassID] = []
    private var releasedIDs: [UUID] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func acquire(source: FolderSource, glassID: GlassID) async throws -> FolderAccessAcquisition {
        if shouldFail { throw RecoveryCenterTestError.injected }
        acquiredGlassIDs.append(glassID)
        return FolderAccessAcquisition(
            handle: FolderAccessHandle(
                id: UUID(),
                glassID: glassID,
                url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
            )
        )
    }

    func release(handleID: UUID) async {
        releasedIDs.append(handleID)
    }

    func acquisitionCount() -> Int { acquiredGlassIDs.count }
    func releaseCount() -> Int { releasedIDs.count }
}

private actor RecoveryCenterInspector: PendingCopyRecoveryInspecting {
    private let disposition: PendingCopyRecoveryDisposition
    private var countValue = 0

    init(disposition: PendingCopyRecoveryDisposition) {
        self.disposition = disposition
    }

    func assess(
        _ record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async -> PendingCopyRecoveryAssessment {
        countValue += 1
        return PendingCopyRecoveryAssessment(record: record, disposition: disposition)
    }

    func count() -> Int { countValue }
}

private actor RecoveryCenterCleaner: PendingCopyOwnedStagingCleaning {
    private let shouldFail: Bool
    private var cleanedIDs: [UUID] = []

    init(shouldFail: Bool = false) {
        self.shouldFail = shouldFail
    }

    func removeOwnedStaging(
        record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async throws {
        if shouldFail { throw RecoveryCenterTestError.injected }
        cleanedIDs.append(record.operationID)
    }

    func cleaned() -> [UUID] { cleanedIDs }
}

private func makeCenterConfiguration(glassID: GlassID) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: glassID,
        title: "Documents",
        source: FolderSource(
            bookmarkData: Data([1, 2, 3]),
            lastKnownPath: "/tmp/Documents"
        ),
        placement: GlassPlacement(x: 0, y: 0)
    )
}

private func makeCenterRecord(
    glassID: GlassID,
    createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "report.txt",
        expectedSize: 7,
        stagingResourceIdentifier: "identity",
        createdAt: createdAt,
        state: .staging
    )
}

private func makeRecoveryCenterUseCase(
    records: [PendingCopyRecord],
    configurations: [GlassConfiguration],
    accessController: RecoveryCenterAccessController,
    inspector: RecoveryCenterInspector,
    cleaner: RecoveryCenterCleaner = RecoveryCenterCleaner()
) -> (PendingCopyRecoveryCenterUseCase, RecoveryCenterStore) {
    let store = RecoveryCenterStore(records: records)
    let execution = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: store,
        recoveryInspector: inspector,
        ownedStagingCleaner: cleaner
    )
    return (
        PendingCopyRecoveryCenterUseCase(
            pendingCopyStore: store,
            configurationStore: RecoveryCenterConfigurationStore(configurations: configurations),
            accessController: accessController,
            recoveryInspector: inspector,
            recoveryExecution: execution
        ),
        store
    )
}

@Test
func recoveryCenterListingUsesShortLivedAccessAndReturnsFreshPlan() async throws {
    let glassID = GlassID()
    let record = makeCenterRecord(glassID: glassID)
    let access = RecoveryCenterAccessController()
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, _) = makeRecoveryCenterUseCase(
        records: [record],
        configurations: [try makeCenterConfiguration(glassID: glassID)],
        accessController: access,
        inspector: inspector
    )

    let items = try await useCase.loadItems()

    #expect(items.count == 1)
    #expect(items[0].glassTitle == "Documents")
    #expect(items[0].state == .assessed(.metadataOnly))
    #expect(items[0].actions == [.discardMetadata])
    #expect(await access.acquisitionCount() == 1)
    #expect(await access.releaseCount() == 1)
    #expect(await inspector.count() == 1)
}

@Test
func recoveryCenterListingOffersReconnectWhenDestinationAccessFails() async throws {
    let glassID = GlassID()
    let record = makeCenterRecord(glassID: glassID)
    let access = RecoveryCenterAccessController(shouldFail: true)
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, _) = makeRecoveryCenterUseCase(
        records: [record],
        configurations: [try makeCenterConfiguration(glassID: glassID)],
        accessController: access,
        inspector: inspector
    )

    let items = try await useCase.loadItems()

    #expect(items[0].state == .destinationUnavailable)
    #expect(items[0].actions == [.reconnectDestination])
    #expect(await access.releaseCount() == 0)
    #expect(await inspector.count() == 0)
}

@Test
func recoveryCenterListingDoesNotGuessWhenConfigurationIsMissing() async throws {
    let record = makeCenterRecord(glassID: GlassID())
    let access = RecoveryCenterAccessController()
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, _) = makeRecoveryCenterUseCase(
        records: [record],
        configurations: [],
        accessController: access,
        inspector: inspector
    )

    let items = try await useCase.loadItems()

    #expect(items[0].state == .configurationMissing)
    #expect(items[0].actions.isEmpty)
    #expect(await access.acquisitionCount() == 0)
    #expect(await inspector.count() == 0)
}

@Test
func recoveryCenterMutationReloadsRecordAndReleasesTemporaryAccess() async throws {
    let glassID = GlassID()
    let record = makeCenterRecord(glassID: glassID)
    let access = RecoveryCenterAccessController()
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, store) = makeRecoveryCenterUseCase(
        records: [record],
        configurations: [try makeCenterConfiguration(glassID: glassID)],
        accessController: access,
        inspector: inspector
    )

    try await useCase.executeMutation(
        action: .discardMetadata,
        operationID: record.operationID
    )

    #expect(await store.removals() == [record.operationID])
    #expect(await access.acquisitionCount() == 1)
    #expect(await access.releaseCount() == 1)
    #expect(await inspector.count() == 1)
}

@Test
func recoveryCenterMutationReleasesAccessWhenConcreteCleanupFails() async throws {
    let glassID = GlassID()
    let record = makeCenterRecord(glassID: glassID)
    let access = RecoveryCenterAccessController()
    let verification = PendingCopyFileVerification(
        size: .matchesExpectedSize,
        resourceIdentity: .matchesRecordedIdentity
    )
    let inspector = RecoveryCenterInspector(disposition: .stagingPresent(verification))
    let cleaner = RecoveryCenterCleaner(shouldFail: true)
    let (useCase, _) = makeRecoveryCenterUseCase(
        records: [record],
        configurations: [try makeCenterConfiguration(glassID: glassID)],
        accessController: access,
        inspector: inspector,
        cleaner: cleaner
    )

    do {
        try await useCase.executeMutation(
            action: .removeOwnedStaging,
            operationID: record.operationID
        )
        Issue.record("Expected mutationFailed")
    } catch let error as PendingCopyRecoveryCenterError {
        #expect(error == .mutationFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await access.releaseCount() == 1)
}
