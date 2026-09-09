import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeRecoveryRecord(
    operationID: UUID = UUID(),
    glassID: GlassID,
    finalFilename: String = "payload.txt",
    expectedSize: Int64? = 7,
    stagingResourceIdentifier: String? = nil,
    state: PendingCopyState = .verifying
) -> PendingCopyRecord {
    PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: finalFilename,
        expectedSize: expectedSize,
        stagingResourceIdentifier: stagingResourceIdentifier,
        state: state
    )
}

private func makeRecoveryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-recovery-inspector-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func resourceIdentifier(for url: URL) throws -> String? {
    try PendingCopyFileIdentity.createToken(
        at: url,
        fileManager: .default
    )
}

private func expectedVerification(
    size: PendingCopySizeVerification,
    identity: PendingCopyResourceIdentityVerification
) -> PendingCopyFileVerification {
    PendingCopyFileVerification(size: size, resourceIdentity: identity)
}

@Test
func recoveryAssessmentClassifiesMetadataOnly() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let record = makeRecoveryRecord(glassID: glassID)
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .metadataOnly)
}

@Test
func recoveryAssessmentVerifiesStagingResourceIdentity() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let operationID = UUID()
    let payload = Data("payload".utf8)
    let stagingName = ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    let staging = root.appendingPathComponent(stagingName)
    try payload.write(to: staging)
    let observedIdentity = try resourceIdentifier(for: staging)
    let record = makeRecoveryRecord(
        operationID: operationID,
        glassID: glassID,
        expectedSize: Int64(payload.count),
        stagingResourceIdentifier: observedIdentity
    )
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(
        assessment.disposition == .stagingPresent(
            expectedVerification(
                size: .matchesExpectedSize,
                identity: observedIdentity == nil
                    ? .recordedIdentityUnavailable
                    : .matchesRecordedIdentity
            )
        )
    )
}

@Test
func recoveryAssessmentPreservesStagingSizeMismatchAndMissingRecordedIdentity() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let record = makeRecoveryRecord(glassID: glassID, expectedSize: 100)
    let staging = root.appendingPathComponent(record.stagingFilename)
    try Data("short".utf8).write(to: staging)
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(
        assessment.disposition == .stagingPresent(
            expectedVerification(
                size: .sizeMismatch(expected: 100, actual: 5),
                identity: .recordedIdentityUnavailable
            )
        )
    )
}

@Test
func recoveryAssessmentDetectsStagingIdentityMismatch() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let stagingRecord = makeRecoveryRecord(glassID: glassID)
    let staging = root.appendingPathComponent(stagingRecord.stagingFilename)
    try Data("payload".utf8).write(to: staging)
    let observedIdentityCandidate = try resourceIdentifier(for: staging)
    let observedIdentity = try #require(observedIdentityCandidate)
    let recordedIdentity = "xattr-v1:\(UUID().uuidString.lowercased())"
    #expect(recordedIdentity != observedIdentity)
    let record = makeRecoveryRecord(
        operationID: stagingRecord.operationID,
        glassID: glassID,
        stagingResourceIdentifier: recordedIdentity
    )
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(
        assessment.disposition == .stagingPresent(
            expectedVerification(
                size: .matchesExpectedSize,
                identity: .mismatchesRecordedIdentity
            )
        )
    )
}

@Test
func finalAfterSameDirectoryRenameRetainsRecordedStagingIdentity() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let operationID = UUID()
    let payload = Data("payload".utf8)
    let stagingName = ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    let staging = root.appendingPathComponent(stagingName)
    let final = root.appendingPathComponent("payload.txt")
    try payload.write(to: staging)
    let stagingIdentity = try resourceIdentifier(for: staging)
    try FileManager.default.moveItem(at: staging, to: final)

    let record = makeRecoveryRecord(
        operationID: operationID,
        glassID: glassID,
        expectedSize: Int64(payload.count),
        stagingResourceIdentifier: stagingIdentity,
        state: .committing
    )
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(
        assessment.disposition == .finalPresent(
            expectedVerification(
                size: .matchesExpectedSize,
                identity: stagingIdentity == nil
                    ? .recordedIdentityUnavailable
                    : .matchesRecordedIdentity
            )
        )
    )
}

@Test
func recoveryAssessmentClassifiesStagingAndFinalAsConflictWithIndependentIdentity() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let operationID = UUID()
    let stagingName = ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    let staging = root.appendingPathComponent(stagingName)
    let final = root.appendingPathComponent("payload.txt")
    try Data("staging".utf8).write(to: staging)
    try Data("final!!".utf8).write(to: final)
    let stagingIdentity = try resourceIdentifier(for: staging)
    let finalIdentity = try resourceIdentifier(for: final)
    let record = makeRecoveryRecord(
        operationID: operationID,
        glassID: glassID,
        stagingResourceIdentifier: stagingIdentity
    )
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    let stagingIdentityVerification: PendingCopyResourceIdentityVerification = stagingIdentity == nil
        ? .recordedIdentityUnavailable
        : .matchesRecordedIdentity
    let finalIdentityVerification: PendingCopyResourceIdentityVerification
    if stagingIdentity == nil {
        finalIdentityVerification = .recordedIdentityUnavailable
    } else if finalIdentity == nil {
        finalIdentityVerification = .observedIdentityUnavailable
    } else if stagingIdentity == finalIdentity {
        finalIdentityVerification = .matchesRecordedIdentity
    } else {
        finalIdentityVerification = .mismatchesRecordedIdentity
    }

    #expect(
        assessment.disposition == .stagingAndFinalPresent(
            staging: expectedVerification(
                size: .matchesExpectedSize,
                identity: stagingIdentityVerification
            ),
            final: expectedVerification(
                size: .matchesExpectedSize,
                identity: finalIdentityVerification
            )
        )
    )
}

@Test
func recoveryAssessmentRejectsRecordThatDoesNotProveStagingOwnership() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let operationID = UUID()
    let record = PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-someone-else.partial",
        finalFilename: "payload.txt",
        expectedSize: nil,
        state: .staging
    )
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .invalidRecord)
}

@Test
func recoveryAssessmentRejectsFinalPathTraversalMetadata() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let record = makeRecoveryRecord(
        glassID: glassID,
        finalFilename: "../escaped.txt"
    )
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .invalidRecord)
    #expect(!FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
}

@Test
func recoveryAssessmentDetectsDestinationMismatchBeforeInspection() async {
    let recordGlassID = GlassID()
    let accessGlassID = GlassID()
    let record = makeRecoveryRecord(glassID: recordGlassID)
    let unavailable = URL(fileURLWithPath: "/definitely/not/a/schneeglass/folder", isDirectory: true)
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: accessGlassID, url: unavailable)
    )

    #expect(assessment.disposition == .destinationMismatch)
}

@Test
func recoveryAssessmentClassifiesMissingDestinationAsUnavailable() async {
    let glassID = GlassID()
    let record = makeRecoveryRecord(glassID: glassID)
    let unavailable = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-missing-\(UUID().uuidString)", isDirectory: true)
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: unavailable)
    )

    #expect(assessment.disposition == .destinationUnavailable)
}

@Test
func recoveryAssessmentDoesNotTreatDirectoryAsOwnedPartialFile() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let record = makeRecoveryRecord(glassID: glassID)
    try FileManager.default.createDirectory(
        at: root.appendingPathComponent(record.stagingFilename, isDirectory: true),
        withIntermediateDirectories: true
    )
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .unexpectedFileType)
}
