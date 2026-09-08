import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RecoveryExecutionTestError: Error, Sendable {
    case injected
}

private actor RecoveryExecutionStoreSpy: PendingCopyRecording {
    private let failRemove: Bool
    private var removedIDs: [UUID] = []

    init(failRemove: Bool = false) {
        self.failRemove = failRemove
    }

    func records() async throws -> [PendingCopyRecord] { [] }
    func upsert(_ record: PendingCopyRecord) async throws {}

    func remove(operationID: UUID) async throws {
        if failRemove {
            throw RecoveryExecutionTestError.injected
        }
        removedIDs.append(operationID)
    }

    func removals() -> [UUID] { removedIDs }
}

private actor RecoveryExecutionInspectorStub: PendingCopyRecoveryInspecting {
    private let disposition: PendingCopyRecoveryDisposition
    private var assessmentCount = 0

    init(disposition: PendingCopyRecoveryDisposition) {
        self.disposition = disposition
    }

    func assess(
        _ record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async -> PendingCopyRecoveryAssessment {
        assessmentCount += 1
        return PendingCopyRecoveryAssessment(record: record, disposition: disposition)
    }

    func count() -> Int { assessmentCount }
}

private actor RecoveryExecutionCleanerSpy: PendingCopyOwnedStagingCleaning {
    private let fail: Bool
    private var cleanedIDs: [UUID] = []

    init(fail: Bool = false) {
        self.fail = fail
    }

    func removeOwnedStaging(
        record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async throws {
        if fail {
            throw RecoveryExecutionTestError.injected
        }
        cleanedIDs.append(record.operationID)
    }

    func cleaned() -> [UUID] { cleanedIDs }
}

private func makeRecoveryExecutionRecord(
    glassID: GlassID = GlassID(),
    identity: String? = "identity"
) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "report.txt",
        expectedSize: 7,
        stagingResourceIdentifier: identity,
        state: .staging
    )
}

private func matchingVerification() -> PendingCopyFileVerification {
    PendingCopyFileVerification(
        size: .matchesExpectedSize,
        resourceIdentity: .matchesRecordedIdentity
    )
}

@Test
func recoveryExecutionDiscardsMetadataOnlyAfterFreshEligibilityCheck() async throws {
    let record = makeRecoveryExecutionRecord()
    let store = RecoveryExecutionStoreSpy()
    let inspector = RecoveryExecutionInspectorStub(disposition: .metadataOnly)
    let cleaner = RecoveryExecutionCleanerSpy()
    let useCase = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: store,
        recoveryInspector: inspector,
        ownedStagingCleaner: cleaner
    )

    try await useCase.execute(
        action: .discardMetadata,
        record: record,
        destinationAccess: FolderAccessHandle(glassID: record.destinationGlassID, url: URL(fileURLWithPath: "/tmp"))
    )

    #expect(await inspector.count() == 1)
    #expect(await store.removals() == [record.operationID])
    #expect(await cleaner.cleaned().isEmpty)
}

@Test
func recoveryExecutionRejectsStaleDiscardPlanWithoutMutation() async throws {
    let record = makeRecoveryExecutionRecord()
    let store = RecoveryExecutionStoreSpy()
    let inspector = RecoveryExecutionInspectorStub(
        disposition: .stagingPresent(matchingVerification())
    )
    let cleaner = RecoveryExecutionCleanerSpy()
    let useCase = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: store,
        recoveryInspector: inspector,
        ownedStagingCleaner: cleaner
    )

    do {
        try await useCase.execute(
            action: .discardMetadata,
            record: record,
            destinationAccess: FolderAccessHandle(glassID: record.destinationGlassID, url: URL(fileURLWithPath: "/tmp"))
        )
        Issue.record("Expected actionNotEligible")
    } catch let error as PendingCopyRecoveryExecutionError {
        #expect(error == .actionNotEligible)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await store.removals().isEmpty)
    #expect(await cleaner.cleaned().isEmpty)
}

@Test
func recoveryExecutionCleansOwnedStagingOnlyAfterFreshEligibilityCheck() async throws {
    let record = makeRecoveryExecutionRecord()
    let store = RecoveryExecutionStoreSpy()
    let inspector = RecoveryExecutionInspectorStub(
        disposition: .stagingPresent(matchingVerification())
    )
    let cleaner = RecoveryExecutionCleanerSpy()
    let useCase = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: store,
        recoveryInspector: inspector,
        ownedStagingCleaner: cleaner
    )

    try await useCase.execute(
        action: .removeOwnedStaging,
        record: record,
        destinationAccess: FolderAccessHandle(glassID: record.destinationGlassID, url: URL(fileURLWithPath: "/tmp"))
    )

    #expect(await inspector.count() == 1)
    #expect(await cleaner.cleaned() == [record.operationID])
    #expect(await store.removals().isEmpty)
}

@Test
func recoveryExecutionRejectsIdentityMismatchBeforeCleaner() async throws {
    let record = makeRecoveryExecutionRecord()
    let verification = PendingCopyFileVerification(
        size: .matchesExpectedSize,
        resourceIdentity: .mismatchesRecordedIdentity
    )
    let store = RecoveryExecutionStoreSpy()
    let inspector = RecoveryExecutionInspectorStub(disposition: .stagingPresent(verification))
    let cleaner = RecoveryExecutionCleanerSpy()
    let useCase = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: store,
        recoveryInspector: inspector,
        ownedStagingCleaner: cleaner
    )

    do {
        try await useCase.execute(
            action: .removeOwnedStaging,
            record: record,
            destinationAccess: FolderAccessHandle(glassID: record.destinationGlassID, url: URL(fileURLWithPath: "/tmp"))
        )
        Issue.record("Expected actionNotEligible")
    } catch let error as PendingCopyRecoveryExecutionError {
        #expect(error == .actionNotEligible)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await cleaner.cleaned().isEmpty)
    #expect(await store.removals().isEmpty)
}

@Test
func recoveryExecutionRejectsReadOnlyActionsAtMutationBoundary() async throws {
    let record = makeRecoveryExecutionRecord()
    let store = RecoveryExecutionStoreSpy()
    let inspector = RecoveryExecutionInspectorStub(disposition: .metadataOnly)
    let cleaner = RecoveryExecutionCleanerSpy()
    let useCase = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: store,
        recoveryInspector: inspector,
        ownedStagingCleaner: cleaner
    )

    do {
        try await useCase.execute(
            action: .revealFinal,
            record: record,
            destinationAccess: FolderAccessHandle(glassID: record.destinationGlassID, url: URL(fileURLWithPath: "/tmp"))
        )
        Issue.record("Expected unsupportedAction")
    } catch let error as PendingCopyRecoveryExecutionError {
        #expect(error == .unsupportedAction)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await inspector.count() == 0)
    #expect(await cleaner.cleaned().isEmpty)
    #expect(await store.removals().isEmpty)
}

@Test
func recoveryExecutionMapsMutationFailuresWithoutTryingOtherMutation() async throws {
    let record = makeRecoveryExecutionRecord()
    let failingStore = RecoveryExecutionStoreSpy(failRemove: true)
    let metadataInspector = RecoveryExecutionInspectorStub(disposition: .metadataOnly)
    let cleaner = RecoveryExecutionCleanerSpy()
    let metadataUseCase = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: failingStore,
        recoveryInspector: metadataInspector,
        ownedStagingCleaner: cleaner
    )

    do {
        try await metadataUseCase.execute(
            action: .discardMetadata,
            record: record,
            destinationAccess: FolderAccessHandle(glassID: record.destinationGlassID, url: URL(fileURLWithPath: "/tmp"))
        )
        Issue.record("Expected metadataMutationFailed")
    } catch let error as PendingCopyRecoveryExecutionError {
        #expect(error == .metadataMutationFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    let failingCleaner = RecoveryExecutionCleanerSpy(fail: true)
    let stagingInspector = RecoveryExecutionInspectorStub(
        disposition: .stagingPresent(matchingVerification())
    )
    let stagingUseCase = PendingCopyRecoveryExecutionUseCase(
        pendingCopyStore: RecoveryExecutionStoreSpy(),
        recoveryInspector: stagingInspector,
        ownedStagingCleaner: failingCleaner
    )

    do {
        try await stagingUseCase.execute(
            action: .removeOwnedStaging,
            record: record,
            destinationAccess: FolderAccessHandle(glassID: record.destinationGlassID, url: URL(fileURLWithPath: "/tmp"))
        )
        Issue.record("Expected ownedStagingCleanupFailed")
    } catch let error as PendingCopyRecoveryExecutionError {
        #expect(error == .ownedStagingCleanupFailed)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
