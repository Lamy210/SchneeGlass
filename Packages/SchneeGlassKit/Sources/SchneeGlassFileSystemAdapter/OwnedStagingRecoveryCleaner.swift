import Darwin
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
/// by itself. This adapter pins the current staging inode with `O_NOFOLLOW`, then revalidates the
/// exact record shape, physical file type, path-to-FD identity, and persisted xattr ownership proof
/// inside an `NSFileCoordinator` delete scope before calling `removeItem`.
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

        // Classify the directory entry itself before opening it. `O_NOFOLLOW` intentionally rejects
        // symlinks with ELOOP, but a symlink is not the same state as a missing staging file. Keeping
        // this distinction explicit preserves the recovery contract and avoids presenting a replaced
        // symlink as if the owned partial simply disappeared.
        switch Self.pathEntryType(at: stagingURL) {
        case .missing:
            throw OwnedStagingRecoveryCleanupError.stagingMissing
        case .regular:
            break
        case .other:
            throw OwnedStagingRecoveryCleanupError.unexpectedFileType
        case .unavailable:
            throw OwnedStagingRecoveryCleanupError.removalFailed
        }

        guard let stagingDescriptor = Self.openReadOnlyNoFollow(stagingURL) else {
            // The entry was regular at the classification point but changed before open. Do not
            // follow the replacement and do not claim ownership of it.
            throw OwnedStagingRecoveryCleanupError.resourceIdentityMismatch
        }
        defer { close(stagingDescriptor) }

        try Self.revalidateOwnedStaging(
            at: stagingURL,
            expectedDestination: destination,
            expectedFilename: record.stagingFilename,
            recordedIdentity: recordedIdentity,
            stagingDescriptor: stagingDescriptor,
            fileManager: fileManager
        )

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
                    stagingDescriptor: stagingDescriptor,
                    fileManager: fileManager
                )

                // Keep the final check adjacent to the only permitted deletion call. A path that
                // was unlinked/recreated after the descriptor was opened is rejected.
                guard PendingCopyFileIdentity.descriptorMatchesPath(
                    stagingDescriptor,
                    pathURL: coordinatedURL
                ) else {
                    throw OwnedStagingRecoveryCleanupError.resourceIdentityMismatch
                }

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

    private enum PathEntryType {
        case missing
        case regular
        case other
        case unavailable
    }

    private static func pathEntryType(at url: URL) -> PathEntryType {
        var pathStat = stat()
        let result = url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return lstat(path, &pathStat)
        }

        guard result == 0 else {
            return errno == ENOENT ? .missing : .unavailable
        }

        return (pathStat.st_mode & S_IFMT) == S_IFREG ? .regular : .other
    }

    private static func revalidateOwnedStaging(
        at url: URL,
        expectedDestination: URL,
        expectedFilename: String,
        recordedIdentity: String,
        stagingDescriptor: Int32,
        fileManager: FileManager
    ) throws {
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent() == expectedDestination,
              candidate.lastPathComponent == expectedFilename
        else {
            throw OwnedStagingRecoveryCleanupError.invalidRecord
        }

        guard PendingCopyFileIdentity.descriptorMatchesPath(
            stagingDescriptor,
            pathURL: candidate
        ) else {
            throw OwnedStagingRecoveryCleanupError.resourceIdentityMismatch
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

        var descriptorStat = stat()
        guard fstat(stagingDescriptor, &descriptorStat) == 0,
              (descriptorStat.st_mode & S_IFMT) == S_IFREG
        else {
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

        guard let observedIdentity = PendingCopyFileIdentity.token(
            onFileDescriptor: stagingDescriptor
        ) else {
            throw OwnedStagingRecoveryCleanupError.resourceIdentityUnavailable
        }
        guard observedIdentity == recordedIdentity else {
            throw OwnedStagingRecoveryCleanupError.resourceIdentityMismatch
        }
    }

    private static func openReadOnlyNoFollow(_ url: URL) -> Int32? {
        url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return nil
            }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            return descriptor >= 0 ? descriptor : nil
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
