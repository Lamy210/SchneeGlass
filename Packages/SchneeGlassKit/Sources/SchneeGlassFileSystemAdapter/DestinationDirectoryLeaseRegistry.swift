import Darwin
import Foundation
import SchneeGlassApplication
import SchneeGlassDomain

enum DestinationDirectoryLeaseError: Error, Hashable, Sendable {
    case destinationUnavailable
    case identityMismatch
    case permissionDenied
    case exclusiveRenameUnsupported
    case operationNotBound
    case descriptorDuplicationFailed(Int32)
}

/// Pins the physical destination directory for one copy batch.
///
/// A selected folder URL is not mutation authority by itself: another process can rename or replace
/// that pathname after planning. This registry opens the directory with `O_NOFOLLOW`, verifies the
/// access/plan identity while the path still names that descriptor, and binds every copy operation
/// ID to the same open directory inode. Production staging creation and commit then use duplicated
/// descriptors from this lease rather than resolving the destination pathname again.
actor DestinationDirectoryLeaseRegistry {
    private struct Lease {
        let descriptor: Int32
        let url: URL
        let operationIDs: Set<UUID>
    }

    private var leasesByBatchID: [UUID: Lease] = [:]
    private var batchIDByOperationID: [UUID: UUID] = [:]

    func bind(_ request: AuthorizedCopyBatchRequest) throws {
        let plan = request.plan
        let access = request.destinationAccess
        let destination = access.url.standardizedFileURL

        guard access.glassID == plan.destination.glassID,
              destination == plan.destination.url.standardizedFileURL,
              leasesByBatchID[plan.batchID] == nil,
              !plan.items.isEmpty
        else {
            throw DestinationDirectoryLeaseError.destinationUnavailable
        }

        let operationIDs = Set(plan.items.map(\.operationID))
        guard operationIDs.count == plan.items.count,
              operationIDs.allSatisfy({ batchIDByOperationID[$0] == nil })
        else {
            throw DestinationDirectoryLeaseError.destinationUnavailable
        }

        let descriptor = try Self.openDirectoryNoFollow(destination)
        do {
            try Self.verifyInitialIdentity(
                descriptor: descriptor,
                url: destination,
                expectedAccessFingerprint: access.fingerprint,
                expectedPlanResourceIdentifier: plan.destination.folderIdentity.resourceIdentifier
            )
        } catch {
            close(descriptor)
            throw error
        }

        leasesByBatchID[plan.batchID] = Lease(
            descriptor: descriptor,
            url: destination,
            operationIDs: operationIDs
        )
        for operationID in operationIDs {
            batchIDByOperationID[operationID] = plan.batchID
        }
    }

    /// Returns a caller-owned duplicate of the pinned directory descriptor. The caller must close it.
    func duplicateDescriptor(operationID: UUID) throws -> Int32 {
        guard let batchID = batchIDByOperationID[operationID],
              let lease = leasesByBatchID[batchID],
              lease.operationIDs.contains(operationID)
        else {
            throw DestinationDirectoryLeaseError.operationNotBound
        }

        let duplicate = fcntl(lease.descriptor, F_DUPFD_CLOEXEC, 0)
        guard duplicate >= 0 else {
            throw DestinationDirectoryLeaseError.descriptorDuplicationFailed(errno)
        }
        return duplicate
    }

    /// Checks the original pinned directory, even if its pathname has since been renamed/replaced.
    /// This is used only to decide whether pending-copy recovery metadata must be retained.
    func itemExists(operationID: UUID, filename: String) -> Bool {
        guard let batchID = batchIDByOperationID[operationID],
              let lease = leasesByBatchID[batchID],
              Self.isSinglePathComponent(filename)
        else {
            return false
        }

        return filename.withCString { name in
            var metadata = stat()
            return fstatat(lease.descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0
        }
    }

    func activeLeaseCount() -> Int {
        leasesByBatchID.count
    }

    func release(batchID: UUID) {
        guard let lease = leasesByBatchID.removeValue(forKey: batchID) else {
            return
        }
        for operationID in lease.operationIDs where batchIDByOperationID[operationID] == batchID {
            batchIDByOperationID.removeValue(forKey: operationID)
        }
        close(lease.descriptor)
    }

    private static func openDirectoryNoFollow(_ url: URL) throws -> Int32 {
        let result = url.standardizedFileURL.withUnsafeFileSystemRepresentation {
            path -> (descriptor: Int32, error: Int32)? in
            guard let path else {
                return nil
            }
            let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
            return (descriptor, descriptor >= 0 ? 0 : errno)
        }

        guard let result else {
            throw DestinationDirectoryLeaseError.destinationUnavailable
        }
        guard result.descriptor >= 0 else {
            switch result.error {
            case EACCES, EPERM:
                throw DestinationDirectoryLeaseError.permissionDenied
            default:
                throw DestinationDirectoryLeaseError.destinationUnavailable
            }
        }
        return result.descriptor
    }

    private static func verifyInitialIdentity(
        descriptor: Int32,
        url: URL,
        expectedAccessFingerprint: ResourceFingerprint?,
        expectedPlanResourceIdentifier: String?
    ) throws {
        var descriptorMetadata = stat()
        guard fstat(descriptor, &descriptorMetadata) == 0,
              (descriptorMetadata.st_mode & S_IFMT) == S_IFDIR,
              descriptorMatchesPath(descriptor, url: url)
        else {
            throw DestinationDirectoryLeaseError.identityMismatch
        }

        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .volumeIdentifierKey,
                .fileResourceIdentifierKey,
                .volumeSupportsExclusiveRenamingKey,
            ])
        } catch {
            throw DestinationDirectoryLeaseError.destinationUnavailable
        }

        // Bracket path-based resource-value lookup with descriptor/path checks. A replacement during
        // lookup cannot become the pinned mutation authority without failing one of these checks.
        guard descriptorMatchesPath(descriptor, url: url) else {
            throw DestinationDirectoryLeaseError.identityMismatch
        }

        let observedVolumeIdentifier = values.volumeIdentifier.map { String(describing: $0) }
        let observedResourceIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }

        if let expectedVolumeIdentifier = expectedAccessFingerprint?.volumeIdentifier,
           observedVolumeIdentifier != expectedVolumeIdentifier
        {
            throw DestinationDirectoryLeaseError.identityMismatch
        }
        if let expectedResourceIdentifier = expectedAccessFingerprint?.resourceIdentifier,
           observedResourceIdentifier != expectedResourceIdentifier
        {
            throw DestinationDirectoryLeaseError.identityMismatch
        }
        if let expectedPlanResourceIdentifier,
           observedResourceIdentifier != expectedPlanResourceIdentifier
        {
            throw DestinationDirectoryLeaseError.identityMismatch
        }

        guard values.volumeSupportsExclusiveRenaming == true else {
            throw DestinationDirectoryLeaseError.exclusiveRenameUnsupported
        }
    }

    private static func descriptorMatchesPath(_ descriptor: Int32, url: URL) -> Bool {
        var descriptorMetadata = stat()
        guard fstat(descriptor, &descriptorMetadata) == 0 else {
            return false
        }

        return url.standardizedFileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return false
            }
            var pathMetadata = stat()
            guard lstat(path, &pathMetadata) == 0,
                  (pathMetadata.st_mode & S_IFMT) == S_IFDIR
            else {
                return false
            }
            return descriptorMetadata.st_dev == pathMetadata.st_dev
                && descriptorMetadata.st_ino == pathMetadata.st_ino
        }
    }

    private static func isSinglePathComponent(_ value: String) -> Bool {
        !value.isEmpty && (value as NSString).lastPathComponent == value
    }
}
