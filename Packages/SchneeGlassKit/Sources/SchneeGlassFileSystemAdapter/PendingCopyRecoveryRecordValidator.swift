import Foundation
import SchneeGlassApplication

enum PendingCopyRecoveryRecordValidator {
    static func isValid(_ record: PendingCopyRecord) -> Bool {
        let expectedStaging = ".schneeglass-copy-\(record.operationID.uuidString.lowercased()).partial"
        guard record.stagingFilename == expectedStaging,
              isSinglePathComponent(record.stagingFilename),
              isSinglePathComponent(record.finalFilename),
              record.stagingFilename != record.finalFilename
        else {
            return false
        }

        return true
    }

    private static func isSinglePathComponent(_ filename: String) -> Bool {
        guard !filename.isEmpty else {
            return false
        }
        return (filename as NSString).lastPathComponent == filename
    }
}
