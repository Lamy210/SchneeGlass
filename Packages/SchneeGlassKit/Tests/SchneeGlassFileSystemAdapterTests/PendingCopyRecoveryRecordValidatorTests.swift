import Foundation
import SchneeGlassApplication
import SchneeGlassDomain
import Testing
@testable import SchneeGlassFileSystemAdapter

private func recoveryValidatorRecord(finalFilename: String) -> PendingCopyRecord {
    let operationID = UUID()
    return PendingCopyRecord(
        operationID: operationID,
        batchID: UUID(),
        destinationGlassID: GlassID(),
        stagingFilename: ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial",
        finalFilename: finalFilename,
        expectedSize: 1,
        state: .recorded
    )
}

@Test
func recoveryRecordValidatorRejectsCurrentDirectoryComponent() {
    let record = recoveryValidatorRecord(finalFilename: ".")

    #expect(PendingCopyRecoveryRecordValidator.isValid(record) == false)
}

@Test
func recoveryRecordValidatorRejectsParentDirectoryComponent() {
    let record = recoveryValidatorRecord(finalFilename: "..")

    #expect(PendingCopyRecoveryRecordValidator.isValid(record) == false)
}

@Test
func recoveryRecordValidatorRejectsEmbeddedNULFinalFilename() {
    let record = recoveryValidatorRecord(finalFilename: "payload\0shadow.txt")

    #expect(PendingCopyRecoveryRecordValidator.isValid(record) == false)
}
