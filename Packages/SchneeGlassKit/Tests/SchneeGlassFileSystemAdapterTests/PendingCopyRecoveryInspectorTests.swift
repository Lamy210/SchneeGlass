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
    state: PendingCopyState = .verifying
) -> PendingCopyRecord {
    PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: finalFilename,
        expectedSize: expectedSize,
        state: state
    )
}

private func makeRecoveryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-recovery-inspector-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
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
func recoveryAssessmentClassifiesVerifiedStaging() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let payload = Data("payload".utf8)
    let record = makeRecoveryRecord(
        glassID: glassID,
        expectedSize: Int64(payload.count)
    )
    let staging = root.appendingPathComponent(record.stagingFilename)
    try payload.write(to: staging)
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .stagingPresent(.matchesExpectedSize))
}

@Test
func recoveryAssessmentPreservesStagingSizeMismatch() async throws {
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
            .sizeMismatch(expected: 100, actual: 5)
        )
    )
}

@Test
func recoveryAssessmentClassifiesFinalWithoutClaimingOwnership() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let payload = Data("payload".utf8)
    let record = makeRecoveryRecord(
        glassID: glassID,
        expectedSize: Int64(payload.count),
        state: .committing
    )
    let final = root.appendingPathComponent(record.finalFilename)
    try payload.write(to: final)
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .finalPresent(.matchesExpectedSize))
}

@Test
func recoveryAssessmentClassifiesStagingAndFinalAsConflict() async throws {
    let root = try makeRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let glassID = GlassID()
    let record = makeRecoveryRecord(glassID: glassID)
    try Data("staging".utf8).write(to: root.appendingPathComponent(record.stagingFilename))
    try Data("final!!".utf8).write(to: root.appendingPathComponent(record.finalFilename))
    let inspector = PendingCopyRecoveryInspector()

    let assessment = await inspector.assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .stagingAndFinalPresent)
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
