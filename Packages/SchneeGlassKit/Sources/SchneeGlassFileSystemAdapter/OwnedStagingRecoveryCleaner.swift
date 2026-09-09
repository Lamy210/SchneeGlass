import Foundation
import SchneeGlassApplication

public enum OwnedStagingRecoveryCleanupError: Error, Hashable, Sendable {
    case destinationMismatch
    case invalidRecord
    case stagingMissing
    case unexpectedFileType
    case resourceIdentityUnavailable
    case resourceIdentityMismatch
    case coordinationFailed
    case removalFailed
}

/// The only v0.1 recovery boundary allowed to delete a pending-copy staging file.
///
/// The caller must have obtained explicit user intent, but that intent is not sufficient authority
/// by itself. This adapter revalidates destination identity, exact record shape, physical file type,
/// and the persisted staging resource identifier inside an `NSFileCoordinator` delete scope before
/// calling `removeItem`.
public actor OwnedStagingRecoveryCleaner: PendingCopyOwnedStagingCleaning {
    private let fileManager: FileManager

    public init() {
        self.fileManager = .default
    }

    init(fileManager: FileManager) {
        self.fileManager = fileManager
    }

    public func removeOwnedStaging(
        record: PendingCopyRecord,
        destinationAccess: FolderAccessHandle
    ) async throws {
        guard record.destinationGlassID == destinationAccess.glassID else {
            throw OwnedStagingRecoveryCleanupError.destinationMismatch
        }
        guard PendingCopyRecoveryRecordValidator.isValid(record) else {
            throw OwnedStagingRecoveryCleanupError.invalidRecord
        }
        guard let recordedIdentity = record.stagingResourceIdentifier else {
            throw OwnedStagingRecoveryCleanupError.resourceIdentityUnavailable
        }

        let destination = destinationAccess.url.standardizedFileURL
        let stagingURL = destination
            .appendingPathComponent(record.stagingFilename, isDirectory: false)
            .standardizedFileURL

        guard stagingURL.deletingLastPathComponent() == destination,
              stagingURL.lastPathComponent == record.stagingFilename
        else {
            throw OwnedStagingRecoveryCleanupError.invalidRecord
        }

        let fileManager = self.fileManager
        var coordinationError: NSError?
        var operationError: OwnedStagingRecoveryCleanupError?

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(
            writingItemAt: stagingURL,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try Self.revalidateOwnedStaging(
                    at: coordinatedURL,
                    expectedDestination: destination,
                    expectedFilename: record.stagingFilename,
                    recordedIdentity: recordedIdentity,
                    fileManager: fileManager
                )
                try fileManager.removeItem(at: coordinatedURL)
            } catch let error as OwnedStagingRecoveryCleanupError {
                operationError = error
            } catch {
                operationError = .removalFailed
            }
        }

        if let operationError {
            throw operationError
        }
        if coordinationError != nil {
            throw OwnedStagingRecoveryCleanupError.coordinationFailed
        }
    }

    private static func revalidateOwnedStaging(
        at url: URL,
        expectedDestination: URL,
        expectedFilename: String,
        recordedIdentity: String,
        fileManager: FileManager
    ) throws {
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent() == expectedDestination,
              candidate.lastPathComponent == expectedFilename
        else {
            throw OwnedStagingRecoveryCleanupError.invalidRecord
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: candidate.path)
        } catch {
            if Self.isMissingFileError(error) {
                throw OwnedStagingRecoveryCleanupError.stagingMissing
            }
            throw OwnedStagingRecoveryCleanupError.removalFailed
        }

        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw OwnedStagingRecoveryCleanupError.unexpectedFileType
        }

        let values: URLResourceValues
        do {
            values = try candidate.resourceValues(forKeys: [
                .isAliasFileKey,
                .isPackageKey,
            ])
        } catch {
            throw OwnedStagingRecoveryCleanupError.removalFailed
        }

        guard values.isAliasFile != true,
              values.isPackage != true
        else {
            throw OwnedStagingRecoveryCleanupError.unexpectedFileType
        }

        guard let observedIdentity = PendingCopyFileIdentity.token(from: attributes) else {
            throw OwnedStagingRecoveryCleanupError.resourceIdentityUnavailable
        }
        guard observedIdentity == recordedIdentity else {
            throw OwnedStagingRecoveryCleanupError.resourceIdentityMismatch
        }
    }

    private static func isMissingFileError(_ error: Error) -> Bool {
        let cocoa = error as NSError
        guard cocoa.domain == NSCocoaErrorDomain else {
            return false
        }
        return cocoa.code == CocoaError.Code.fileNoSuchFile.rawValue
            || cocoa.code == CocoaError.Code.fileReadNoSuchFile.rawValue
    }
}
