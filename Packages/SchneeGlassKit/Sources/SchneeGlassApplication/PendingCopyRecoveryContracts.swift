import Foundation

public enum PendingCopyFileVerification: Hashable, Sendable {
    case matchesExpectedSize
    case sizeMismatch(expected: Int64, actual: Int64)
    case expectedSizeUnavailable(actual: Int64)
}

public enum PendingCopyRecoveryDisposition: Hashable, Sendable {
    /// Recovery metadata exists, but neither staging nor final data exists.
    /// Removing only the metadata is safe; no user file needs to be mutated.
    case metadataOnly

    /// An app-owned staging file remains and should be surfaced for explicit recovery.
    case stagingPresent(PendingCopyFileVerification)

    /// A final file exists but the staging file does not. The final file must never
    /// be deleted or overwritten automatically because ownership cannot be proven
    /// after a restart from filename/size alone.
    case finalPresent(PendingCopyFileVerification)

    /// Staging and final files both exist. This is a collision/conflict state and
    /// requires user review; automatic cleanup is forbidden.
    case stagingAndFinalPresent

    /// Persisted metadata does not prove ownership of the referenced staging file
    /// or contains an unsafe filename/path component.
    case invalidRecord

    /// The recovery record belongs to a different Glass than the supplied access handle.
    case destinationMismatch

    /// The destination folder cannot currently be inspected.
    case destinationUnavailable

    /// A referenced staging/final path exists but is not a regular file.
    case unexpectedFileType
}

public struct PendingCopyRecoveryAssessment: Hashable, Sendable, Identifiable {
    public var id: UUID { record.operationID }

    public let record: PendingCopyRecord
    public let disposition: PendingCopyRecoveryDisposition

    public init(
        record: PendingCopyRecord,
        disposition: PendingCopyRecoveryDisposition
    ) {
        self.record = record
        self.disposition = disposition
    }
}

public protocol PendingCopyRecoveryInspecting: Sendable {
    func assess(
        _ record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async -> PendingCopyRecoveryAssessment
}
