import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RecoveryCenterTestError: Error, Sendable { case injected }

private actor RecoveryCenterStore: PendingCopyRecording {
    private var values: [PendingCopyRecord]
    private var removedIDs: [UUID] = []

    init(records: [PendingCopyRecord]) { self.values = records }

    func records() async throws -> [PendingCopyRecord] { values }
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
    init(configurations: [GlassConfiguration]) { self.configurations = configurations }
    func load() async throws -> [GlassConfiguration] { configurations }
    func save(_ configurations: [GlassConfiguration]) async throws {}
}

private actor RecoveryCenterAccessController: FolderAccessControlling {
    private let shouldFail: Bool
    private var acquisitions = 0
    private var releases = 0

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func acquire(source: FolderSource, glassID: GlassID) async throws -> FolderAccessAcquisition {
        if shouldFail { throw RecoveryCenterTestError.injected }
        acquisitions += 1
        return FolderAccessAcquisition(
            handle: FolderAccessHandle(
                glassID: glassID,
                url: URL(fileURLWithPath: source.lastKnownPath, isDirectory: true)
            )
        )
    }

    func release(handleID: UUID) async { releases += 1 }
    func acquisitionCount() -> Int { acquisitions }
    func releaseCount() -> Int { releases }
}

private actor RecoveryCenterInspector: PendingCopyRecoveryInspecting {
    private let disposition: PendingCopyRecoveryDisposition
    private var assessments = 0

    init(disposition: PendingCopyRecoveryDisposition) { self.disposition = disposition }

    func assess(
        _ record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async -> PendingCopyRecoveryAssessment {
        assessments += 1
        return PendingCopyRecoveryAssessment(record: record, disposition: disposition)
    }

    func count() -> Int { assessments }
}

private actor RecoveryCenterCleaner: PendingCopyOwnedStagingCleaning {
    private let shouldFail: Bool
    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func removeOwnedStaging(
        record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async throws {
        if shouldFail { throw RecoveryCenterTestError.injected }
    }
}

private func centerConfiguration(glassID: GlassID) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: glassID,
        title: "Documents",
        source: FolderSource(bookmarkData: Data([1]), lastKnownPath: "/tmp/Documents"),
        placement: GlassPlacement(x: 0, y: 0)
    )
}

private func centerRecord(glassID: GlassID) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "report.txt",
        expectedSize: 7,
        stagingResourceIdentifier: "identity",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        state: .staging
    )
}

private func centerUseCase(
    record: PendingCopyRecord,
    configurations: [GlassConfiguration],
    access: RecoveryCenterAccessController,
    inspector: RecoveryCenterInspector,
    cleaner: RecoveryCenterCleaner = RecoveryCenterCleaner()
) -> (PendingCopyRecoveryCenterUseCase, RecoveryCenterStore) {
    let store = RecoveryCenterStore(records: [record])
    let execution = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: store,
        recoveryInspector: inspector,
        ownedStagingCleaner: cleaner
    )
    return (
        PendingCopyRecoveryCenterUseCase(
            pendingCopyStore: store,
            configurationStore: RecoveryCenterConfigurationStore(configurations: configurations),
            accessController: access,
            recoveryInspector: inspector,
            recoveryExecution: execution
        ),
        store
    )
}

@Test
func recoveryCenterListingUsesShortLivedAccess() async throws {
    let glassID = GlassID()
    let record = centerRecord(glassID: glassID)
    let access = RecoveryCenterAccessController()
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, _) = centerUseCase(
        record: record,
        configurations: [try centerConfiguration(glassID: glassID)],
        access: access,
        inspector: inspector
    )

    let items = try await useCase.loadItems()

    #expect(items.count == 1)
    #expect(items[0].glassTitle == "Documents")
    #expect(items[0].state == .assessed(.metadataOnly))
    #expect(items[0].actions == [.discardMetadata])
    #expect(await access.acquisitionCount() == 1)
    #expect(await access.releaseCount() == 1)
}

@Test
func recoveryCenterListingOffersReconnectWhenDestinationUnavailable() async throws {
    let glassID = GlassID()
    let record = centerRecord(glassID: glassID)
    let access = RecoveryCenterAccessController(shouldFail: true)
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, _) = centerUseCase(
        record: record,
        configurations: [try centerConfiguration(glassID: glassID)],
        access: access,
        inspector: inspector
    )

    let items = try await useCase.loadItems()

    #expect(items[0].state == .destinationUnavailable)
    #expect(items[0].actions == [.reconnectDestination])
    #expect(await inspector.count() == 0)
}

@Test
func recoveryCenterListingDoesNotGuessWhenConfigurationMissing() async throws {
    let record = centerRecord(glassID: GlassID())
    let access = RecoveryCenterAccessController()
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, _) = centerUseCase(
        record: record,
        configurations: [],
        access: access,
        inspector: inspector
    )

    let items = try await useCase.loadItems()

    #expect(items[0].state == .configurationMissing)
    #expect(items[0].actions.isEmpty)
    #expect(await access.acquisitionCount() == 0)
}

@Test
func recoveryCenterMutationReloadsRecordAndReleasesAccess() async throws {
    let glassID = GlassID()
    let record = centerRecord(glassID: glassID)
    let access = RecoveryCenterAccessController()
    let inspector = RecoveryCenterInspector(disposition: .metadataOnly)
    let (useCase, store) = centerUseCase(
        record: record,
        configurations: [try centerConfiguration(glassID: glassID)],
        access: access,
        inspector: inspector
    )

    try await useCase.executeMutation(action: .discardMetadata, operationID: record.operationID)

    #expect(await store.removals() == [record.operationID])
    #expect(await access.acquisitionCount() == 1)
    #expect(await access.releaseCount() == 1)
}

@Test
func recoveryCenterMutationReleasesAccessOnCleanupFailure() async throws {
    let glassID = GlassID()
    let record = centerRecord(glassID: glassID)
    let access = RecoveryCenterAccessController()
    let verification = PendingCopyFileVerification(
        size: .matchesExpectedSize,
        resourceIdentity: .matchesRecordedIdentity
    )
    let inspector = RecoveryCenterInspector(disposition: .stagingPresent(verification))
    let (useCase, _) = centerUseCase(
        record: record,
        configurations: [try centerConfiguration(glassID: glassID)],
        access: access,
        inspector: inspector,
        cleaner: RecoveryCenterCleaner(shouldFail: true)
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
