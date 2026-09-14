import Darwin
import Foundation

enum DestinationCommitErrorDisposition: Hashable, Sendable {
    case collision
    case stagingMissing
    case destinationUnavailable
    case permissionDenied
    case insufficientSpace
    case commitFailed
}

enum DestinationCommitPreflightErrorDisposition: Hashable, Sendable {
    case stagingMissing
    case unexpectedFileType
    case destinationAbsent
    case permissionDenied
    case commitFailed
}

enum DestinationCommitErrnoClassifier {
    static func classify(_ error: Int32) -> DestinationCommitErrorDisposition {
        switch error {
        case EEXIST:
            return .collision
        case ENOENT:
            return .stagingMissing
        case EROFS:
            return .destinationUnavailable
        case EACCES, EPERM:
            return .permissionDenied
        case ENOSPC, EDQUOT:
            return .insufficientSpace
        default:
            return .commitFailed
        }
    }

    static func classifyStagingOpen(_ error: Int32) -> DestinationCommitPreflightErrorDisposition {
        switch error {
        case ENOENT:
            return .stagingMissing
        case ELOOP:
            return .unexpectedFileType
        case EACCES, EPERM:
            return .permissionDenied
        default:
            return .commitFailed
        }
    }

    static func classifyDestinationLookup(_ error: Int32) -> DestinationCommitPreflightErrorDisposition {
        switch error {
        case ENOENT:
            return .destinationAbsent
        case EACCES, EPERM:
            return .permissionDenied
        default:
            return .commitFailed
        }
    }
}

/// Production staging committer for pinned-source Drop copies.
///
/// Both the staging lookup and final rename are relative to the physical destination directory
/// descriptor captured for the batch. `RENAME_EXCL` makes the no-overwrite rule atomic at the
/// filesystem boundary instead of relying on a path precheck followed by a separate rename.
actor PinnedDestinationStagingCommitter: StagingCommitting {
    private let destinationLeases: DestinationDirectoryLeaseRegistry

    init(destinationLeases: DestinationDirectoryLeaseRegistry) {
        self.destinationLeases = destinationLeases
    }

    func commit(
        stagingURL: URL,
        finalURL: URL,
        authorization: StagingCommitAuthorization
    ) async throws {
        let staging = stagingURL.standardizedFileURL
        let final = finalURL.standardizedFileURL
        let destinationDirectory = final.deletingLastPathComponent().standardizedFileURL

        guard staging.deletingLastPathComponent().standardizedFileURL == destinationDirectory,
              InternalStagingCommitter.isOwnedStagingFilename(staging.lastPathComponent),
              Self.isSinglePathComponent(final.lastPathComponent),
              let operationID = await destinationLeases.operationID(forStagingURL: staging)
        else {
            throw StagingCommitError.invalidStagingFile
        }

        let directoryDescriptor: Int32
        do {
            directoryDescriptor = try await destinationLeases.duplicateDescriptorForCommit(
                operationID: operationID,
                expectedFinalFilename: final.lastPathComponent
            )
        } catch {
            throw StagingCommitError.commitFailed
        }
        defer { close(directoryDescriptor) }

        let stagingDescriptor = try Self.openReadOnlyNoFollow(
            directoryDescriptor: directoryDescriptor,
            filename: staging.lastPathComponent
        )
        defer { close(stagingDescriptor) }

        try Self.revalidateOwnedStaging(
            stagingDescriptor: stagingDescriptor,
            directoryDescriptor: directoryDescriptor,
            filename: staging.lastPathComponent,
            authorization: authorization
        )

        try Self.requireDestinationAbsent(
            directoryDescriptor: directoryDescriptor,
            filename: final.lastPathComponent
        )

        guard PendingCopyFileIdentity.descriptorMatchesDirectoryEntry(
            stagingDescriptor,
            directoryDescriptor: directoryDescriptor,
            filename: staging.lastPathComponent
        ) else {
            throw StagingCommitError.resourceIdentityMismatch
        }

        let renameResult = staging.lastPathComponent.withCString { sourceName in
            final.lastPathComponent.withCString { destinationName in
                renameatx_np(
                    directoryDescriptor,
                    sourceName,
                    directoryDescriptor,
                    destinationName,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard renameResult == 0 else {
            let observedErrno = errno
            switch DestinationCommitErrnoClassifier.classify(observedErrno) {
            case .collision:
                throw StagingCommitError.collision
            case .stagingMissing:
                throw StagingCommitError.stagingMissing
            case .destinationUnavailable:
                throw CopyFileSystemError.destinationUnavailable
            case .permissionDenied:
                throw CopyFileSystemError.permissionDenied
            case .insufficientSpace:
                throw CopyFileSystemError.insufficientSpace
            case .commitFailed:
                throw StagingCommitError.commitFailed
            }
        }

        // The open staging descriptor survives rename. Verify the final directory entry now names
        // that exact inode; if not, recovery metadata remains and the copy fails closed.
        guard PendingCopyFileIdentity.descriptorMatchesDirectoryEntry(
            stagingDescriptor,
            directoryDescriptor: directoryDescriptor,
            filename: final.lastPathComponent
        ) else {
            throw StagingCommitError.resourceIdentityMismatch
        }
    }

    private static func openReadOnlyNoFollow(
        directoryDescriptor: Int32,
        filename: String
    ) throws -> Int32 {
        guard isSinglePathComponent(filename) else {
            throw StagingCommitError.invalidStagingFile
        }

        let result = filename.withCString { name -> (descriptor: Int32, error: Int32) in
            let descriptor = openat(
                directoryDescriptor,
                name,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW
            )
            return (descriptor, descriptor >= 0 ? 0 : errno)
        }
        guard result.descriptor >= 0 else {
            switch DestinationCommitErrnoClassifier.classifyStagingOpen(result.error) {
            case .stagingMissing:
                throw StagingCommitError.stagingMissing
            case .unexpectedFileType:
                throw StagingCommitError.unexpectedFileType
            case .permissionDenied:
                throw CopyFileSystemError.permissionDenied
            case .destinationAbsent,
                 .commitFailed:
                throw StagingCommitError.commitFailed
            }
        }
        return result.descriptor
    }

    private static func revalidateOwnedStaging(
        stagingDescriptor: Int32,
        directoryDescriptor: Int32,
        filename: String,
        authorization: StagingCommitAuthorization
    ) throws {
        guard PendingCopyFileIdentity.descriptorMatchesDirectoryEntry(
            stagingDescriptor,
            directoryDescriptor: directoryDescriptor,
            filename: filename
        ) else {
            throw StagingCommitError.resourceIdentityMismatch
        }

        var metadata = stat()
        guard fstat(stagingDescriptor, &metadata) == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG
        else {
            throw StagingCommitError.unexpectedFileType
        }
        guard Int64(metadata.st_size) == authorization.expectedSize else {
            throw StagingCommitError.sizeMismatch
        }
        guard let token = PendingCopyFileIdentity.token(onFileDescriptor: stagingDescriptor) else {
            throw StagingCommitError.resourceIdentityUnavailable
        }
        guard token == authorization.expectedResourceIdentifier else {
            throw StagingCommitError.resourceIdentityMismatch
        }
    }

    private static func requireDestinationAbsent(
        directoryDescriptor: Int32,
        filename: String
    ) throws {
        guard isSinglePathComponent(filename) else {
            throw StagingCommitError.invalidStagingFile
        }

        let result = filename.withCString { name -> (exists: Bool, error: Int32) in
            var metadata = stat()
            if fstatat(directoryDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
                return (true, 0)
            }
            return (false, errno)
        }
        if result.exists {
            throw StagingCommitError.collision
        }

        switch DestinationCommitErrnoClassifier.classifyDestinationLookup(result.error) {
        case .destinationAbsent:
            return
        case .permissionDenied:
            throw CopyFileSystemError.permissionDenied
        case .stagingMissing,
             .unexpectedFileType,
             .commitFailed:
            throw StagingCommitError.commitFailed
        }
    }

    private static func isSinglePathComponent(_ value: String) -> Bool {
        !value.isEmpty && (value as NSString).lastPathComponent == value
    }
}
