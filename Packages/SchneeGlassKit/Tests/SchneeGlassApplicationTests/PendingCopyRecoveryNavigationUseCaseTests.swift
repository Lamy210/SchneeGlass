import Foundation
@testable import SchneeGlassApplication
import SchneeGlassDomain
import Testing

private enum RecoveryNavigationTestError: Error, Sendable { case injected }

private actor RecoveryNavigationRecordStore: PendingCopyRecording {
    private let values: [PendingCopyRecord]
    init(records: [PendingCopyRecord]) { self.values = records }
    func records() async throws -> [PendingCopyRecord] { values }
    func upsert(_ record: PendingCopyRecord) async throws {}
    func remove(operationID: UUID) async throws {}
}

private actor RecoveryNavigationConfigurationStore: ConfigurationPersisting {
    private let values: [GlassConfiguration]
    init(configurations: [GlassConfiguration]) { self.values = configurations }
    func load() async throws -> [GlassConfiguration] { values }
    func save(_ configurations: [GlassConfiguration]) async throws {}
}

private actor RecoveryNavigationAccessController: FolderAccessControlling {
    private let shouldFail: Bool
    private var acquisitions = 0
    private var releases = 0

    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func acquire(source: FolderSource, glassID: GlassID) async throws -> FolderAccessAcquisition {
        if shouldFail { throw RecoveryNavigationTestError.injected }
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

private actor RecoveryNavigationInspector: PendingCopyRecoveryInspecting {
    private let disposition: PendingCopyRecoveryDisposition
    init(disposition: PendingCopyRecoveryDisposition) { self.disposition = disposition }

    func assess(
        _ record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async -> PendingCopyRecoveryAssessment {
        PendingCopyRecoveryAssessment(record: record, disposition: disposition)
    }
}

@MainActor
private final class RecoveryNavigationFileActor: WorkspaceFileActing {
    private(set) var revealedURLs: [URL] = []
    func open(url: URL) -> Bool { true }
    func reveal(url: URL) { revealedURLs.append(url.standardizedFileURL) }
}

private func recoveryNavigationConfiguration(glassID: GlassID) throws -> GlassConfiguration {
    try GlassConfiguration(
        id: glassID,
        title: "Documents",
        source: FolderSource(
            bookmarkData: Data([1]),
            lastKnownPath: "/tmp/RecoveryNavigation"
        ),
        placement: GlassPlacement(x: 0, y: 0)
    )
}

private func recoveryNavigationRecord(glassID: GlassID) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: "report.txt",
        expectedSize: 7,
        stagingResourceIdentifier: "identity",
        state: .staging
    )
}

@MainActor
private func recoveryNavigationUseCase(
    record: PendingCopyRecord,
    configuration: GlassConfiguration,
    disposition: PendingCopyRecoveryDisposition,
    access: RecoveryNavigationAccessController = RecoveryNavigationAccessController(),
    fileActor: RecoveryNavigationFileActor = RecoveryNavigationFileActor()
) -> PendingCopyRecoveryNavigationUseCase {
    PendingCopyRecoveryNavigationUseCase(
        pendingCopyStore: RecoveryNavigationRecordStore(records: [record]),
        configurationStore: RecoveryNavigationConfigurationStore(configurations: [configuration]),
        accessController: access,
        recoveryInspector: RecoveryNavigationInspector(disposition: disposition),
        fileActor: fileActor
    )
}

@Test
@MainActor
func recoveryNavigationRevealsStagingOnlyAfterFreshEligibility() async throws {
    let glassID = GlassID()
    let record = recoveryNavigationRecord(glassID: glassID)
    let configuration = try recoveryNavigationConfiguration(glassID: glassID)
    let verification = PendingCopyFileVerification(
        size: .matchesExpectedSize,
        resourceIdentity: .mismatchesRecordedIdentity
    )
    let access = RecoveryNavigationAccessController()
    let fileActor = RecoveryNavigationFileActor()
    let useCase = recoveryNavigationUseCase(
        record: record,
        configuration: configuration,
        disposition: .stagingPresent(verification),
        access: access,
        fileActor: fileActor
    )

    try await useCase.reveal(action: .revealStaging, operationID: record.operationID)

    #expect(fileActor.revealedURLs == [
        URL(fileURLWithPath: "/tmp/RecoveryNavigation")
            .appendingPathComponent(record.stagingFilename)
            .standardizedFileURL,
    ])
    #expect(await access.acquisitionCount() == 1)
    #expect(await access.releaseCount() == 1)
}

@Test
@MainActor
func recoveryNavigationRevealsFinalWithoutClaimingOwnership() async throws {
    let glassID = GlassID()
    let record = recoveryNavigationRecord(glassID: glassID)
    let configuration = try recoveryNavigationConfiguration(glassID: glassID)
    let verification = PendingCopyFileVerification(
        size: .sizeMismatch(expected: 7, actual: 9),
        resourceIdentity: .mismatchesRecordedIdentity
    )
    let fileActor = RecoveryNavigationFileActor()
    let useCase = recoveryNavigationUseCase(
        record: record,
        configuration: configuration,
        disposition: .finalPresent(verification),
        fileActor: fileActor
    )

    try await useCase.reveal(action: .revealFinal, operationID: record.operationID)

    #expect(fileActor.revealedURLs == [
        URL(fileURLWithPath: "/tmp/RecoveryNavigation/report.txt").standardizedFileURL,
    ])
}

@Test
@MainActor
func recoveryNavigationRejectsStaleRevealActionAndReleasesAccess() async throws {
    let glassID = GlassID()
    let record = recoveryNavigationRecord(glassID: glassID)
    let configuration = try recoveryNavigationConfiguration(glassID: glassID)
    let access = RecoveryNavigationAccessController()
    let fileActor = RecoveryNavigationFileActor()
    let useCase = recoveryNavigationUseCase(
        record: record,
        configuration: configuration,
        disposition: .metadataOnly,
        access: access,
        fileActor: fileActor
    )

    do {
        try await useCase.reveal(action: .revealStaging, operationID: record.operationID)
        Issue.record("Expected actionNoLongerAvailable")
    } catch let error as PendingCopyRecoveryNavigationError {
        #expect(error == .actionNoLongerAvailable)
    }

    #expect(fileActor.revealedURLs.isEmpty)
    #expect(await access.releaseCount() == 1)
}

@Test
@MainActor
func recoveryNavigationRejectsMutationActionWithoutDestinationAccess() async throws {
    let glassID = GlassID()
    let record = recoveryNavigationRecord(glassID: glassID)
    let configuration = try recoveryNavigationConfiguration(glassID: glassID)
    let access = RecoveryNavigationAccessController()
    let fileActor = RecoveryNavigationFileActor()
    let useCase = recoveryNavigationUseCase(
        record: record,
        configuration: configuration,
        disposition: .metadataOnly,
        access: access,
        fileActor: fileActor
    )

    do {
        try await useCase.reveal(action: .discardMetadata, operationID: record.operationID)
        Issue.record("Expected unsupportedAction")
    } catch let error as PendingCopyRecoveryNavigationError {
        #expect(error == .unsupportedAction)
    }

    #expect(await access.acquisitionCount() == 0)
    #expect(fileActor.revealedURLs.isEmpty)
}

@Test
@MainActor
func recoveryNavigationDestinationFailureDoesNotReveal() async throws {
    let glassID = GlassID()
    let record = recoveryNavigationRecord(glassID: glassID)
    let configuration = try recoveryNavigationConfiguration(glassID: glassID)
    let access = RecoveryNavigationAccessController(shouldFail: true)
    let fileActor = RecoveryNavigationFileActor()
    let useCase = recoveryNavigationUseCase(
        record: record,
        configuration: configuration,
        disposition: .metadataOnly,
        access: access,
        fileActor: fileActor
    )

    do {
        try await useCase.reveal(action: .revealFinal, operationID: record.operationID)
        Issue.record("Expected destinationUnavailable")
    } catch let error as PendingCopyRecoveryNavigationError {
        #expect(error == .destinationUnavailable)
    }

    #expect(fileActor.revealedURLs.isEmpty)
    #expect(await access.releaseCount() == 0)
}
