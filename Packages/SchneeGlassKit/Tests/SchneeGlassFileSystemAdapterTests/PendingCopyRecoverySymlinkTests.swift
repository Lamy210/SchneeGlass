import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func makeSymlinkRecoveryRecord(
    operationID: UUID,
    glassID: GlassID,
    finalFilename: String = "payload.txt"
) -> PendingCopyRecord {
    PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: glassID,
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: finalFilename,
        expectedSize: 7,
        stagingResourceIdentifier: "xattr-v1:\(UUID().uuidString.lowercased())",
        state: .verifying
    )
}

private func makeSymlinkRecoveryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("schneeglass-recovery-symlink-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@Test
func recoveryAssessmentDoesNotFollowStagingSymlink() async throws {
    let root = try makeSymlinkRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let record = makeSymlinkRecoveryRecord(operationID: operationID, glassID: glassID)
    let target = root.appendingPathComponent("target.txt")
    let staging = root.appendingPathComponent(record.stagingFilename)
    let payload = Data("payload".utf8)
    try payload.write(to: target)
    try FileManager.default.createSymbolicLink(at: staging, withDestinationURL: target)

    let assessment = await PendingCopyRecoveryInspector().assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .unexpectedFileType)
    #expect(try Data(contentsOf: target) == payload)
}

@Test
func recoveryAssessmentDoesNotFollowFinalSymlink() async throws {
    let root = try makeSymlinkRecoveryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let glassID = GlassID()
    let operationID = UUID()
    let record = makeSymlinkRecoveryRecord(operationID: operationID, glassID: glassID)
    let target = root.appendingPathComponent("target.txt")
    let final = root.appendingPathComponent(record.finalFilename)
    let payload = Data("payload".utf8)
    try payload.write(to: target)
    try FileManager.default.createSymbolicLink(at: final, withDestinationURL: target)

    let assessment = await PendingCopyRecoveryInspector().assess(
        record,
        destinationAccess: FolderAccessHandle(glassID: glassID, url: root)
    )

    #expect(assessment.disposition == .unexpectedFileType)
    #expect(try Data(contentsOf: target) == payload)
}
