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
/// ID plus its staging/final names to the same open directory inode.
actor DestinationDirectoryLeaseRegistry {
    private struct Lease {
        let descriptor: Int32
        let url: URL
        let operationIDs: Set<UUID>
    }

    private struct OperationBinding {
        let batchID: UUID
        let directoryURL: URL
        let stagingFilename: String
        let finalFilename: String
    }

    static let defaultMaximumActiveLeases = 128

    private let maximumActiveLeases: Int
    private var leasesByBatchID: [UUID: Lease] = [:]
    private var bindingByOperationID: [UUID: OperationBinding] = [:]

    init() {
        self.maximumActiveLeases = Self.defaultMaximumActiveLeases
    }

    init(maximumActiveLeases: Int) {
        precondition(maximumActiveLeases > 0, "Destination lease capacity must be positive")
        self.maximumActiveLeases = maximumActiveLeases
    }

    func bind(_ request: AuthorizedCopyBatchRequest) throws {
        let plan = request.plan
        let access = request.destinationAccess
        let destination = access.url.standardizedFileURL

        guard access.glassID == plan.destination.glassID,
              destination == plan.destination.url.standardizedFileURL,
              plan.destination.capabilities.locationKind != .network,
              plan.destination.capabilities.isWritable,
              leasesByBatchID[plan.batchID] == nil,
              !plan.items.isEmpty
        else {
            throw DestinationDirectoryLeaseError.destinationUnavailable
        }

        // Keep descriptor usage bounded inside SchneeGlass instead of relying on the process-wide
        // RLIMIT_NOFILE failure mode. One destination descriptor is held for each active copy batch.
        guard leasesByBatchID.count < maximumActiveLeases else {
            throw DestinationDirectoryLeaseError.destinationUnavailable
        }

        let operationIDs = Set(plan.items.map(\.operationID))
        guard operationIDs.count == plan.items.count,
              operationIDs.allSatisfy({ bindingByOperationID[$0] == nil }),
              plan.items.allSatisfy({ Self.isSinglePathComponent($0.destinationFilename) })
        else {
            throw DestinationDirectoryLeaseError.destinationUnavailable
        }

        let descriptor = try Self.openDirectoryNoFollow(destination)
        do {
            try Self.verifyInitialIdentity(
                descriptor: descriptor,
                url: destination,
                expectedAccessRuntimeIdentity: access.runtimeDirectoryIdentity,
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
        for item in plan.items {
            bindingByOperationID[item.operationID] = OperationBinding(
                batchID: plan.batchID,
                directoryURL: destination,
                stagingFilename: Self.stagingFilename(operationID: item.operationID),
                finalFilename: item.destinationFilename
            )
        }
    }

    func isBoundDirectory(_ url: URL) -> Bool {
        let candidate = url.standardizedFileURL
        return leasesByBatchID.values.contains { $0.url == candidate }
    }

    /// Returns whether a known staging/final entry exists in the pinned directory. `nil` means the
    /// URL is not part of any active destination lease and callers should not infer authority.
    func itemExists(at url: URL) -> Bool? {
        let candidate = url.standardizedFileURL
        let directory = candidate.deletingLastPathComponent().standardizedFileURL
        let filename = candidate.lastPathComponent
        guard Self.isSinglePathComponent(filename),
              let match = bindingByOperationID.first(where: { _, binding in
                  binding.directoryURL == directory
                      && (binding.stagingFilename == filename || binding.finalFilename == filename)
              }),
              let lease = leasesByBatchID[match.value.batchID]
        else {
            return nil
        }

        return Self.itemExists(
            directoryDescriptor: lease.descriptor,
            filename: filename
        )
    }

    func operationID(forStagingURL url: URL) -> UUID? {
        let candidate = url.standardizedFileURL
        let filename = candidate.lastPathComponent
        guard let operationID = Self.operationID(fromStagingFilename: filename),
              let binding = bindingByOperationID[operationID],
              binding.directoryURL == candidate.deletingLastPathComponent().standardizedFileURL,
              binding.stagingFilename == filename
        else {
            return nil
        }
        return operationID
    }

    /// Returns a caller-owned duplicate of the pinned directory descriptor. The caller must close it.
    func duplicateDescriptor(operationID: UUID) throws -> Int32 {
        guard let binding = bindingByOperationID[operationID],
              let lease = leasesByBatchID[binding.batchID],
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

    func activeLeaseCount() -> Int {
        leasesByBatchID.count
    }

    func release(batchID: UUID) {
        guard let lease = leasesByBatchID.removeValue(forKey: batchID) else {
            return
        }
        for operationID in lease.operationIDs {
            if bindingByOperationID[operationID]?.batchID == batchID {
                bindingByOperationID.removeValue(forKey: operationID)
            }
        }
        close(lease.descriptor)
    }

    static func stagingFilename(operationID: UUID) -> String {
        ".schneeglass-copy-\(operationID.uuidString.lowercased()).partial"
    }

    static func operationID(fromStagingFilename filename: String) -> UUID? {
        let prefix = ".schneeglass-copy-"
        let suffix = ".partial"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else {
            return nil
        }
        let start = filename.index(filename.startIndex, offsetBy: prefix.count)
        let end = filename.index(filename.endIndex, offsetBy: -suffix.count)
        guard start < end else {
            return nil
        }
        return UUID(uuidString: String(filename[start..<end]))
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
        expectedAccessRuntimeIdentity: RuntimeDirectoryIdentity?,
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

        if let expectedAccessRuntimeIdentity {
            let observedDeviceIdentifier = UInt64(truncatingIfNeeded: descriptorMetadata.st_dev)
            let observedObjectIdentifier = UInt64(truncatingIfNeeded: descriptorMetadata.st_ino)
            guard observedDeviceIdentifier == expectedAccessRuntimeIdentity.deviceIdentifier,
                  observedObjectIdentifier == expectedAccessRuntimeIdentity.objectIdentifier
            else {
                throw DestinationDirectoryLeaseError.identityMismatch
            }
        }

        // A volume identifier alone cannot distinguish two directories on the same volume. Runtime
        // descriptor identity, an acquired directory resource ID, or the authoritative plan's
        // directory resource ID must prove which directory is intended before mutation can begin.
        guard expectedAccessRuntimeIdentity != nil
                || expectedAccessFingerprint?.resourceIdentifier != nil
                || expectedPlanResourceIdentifier != nil
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

    private static func itemExists(
        directoryDescriptor: Int32,
        filename: String
    ) -> Bool {
        filename.withCString { name in
            var metadata = stat()
            return fstatat(directoryDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0
        }
    }

    private static func isSinglePathComponent(_ value: String) -> Bool {
        !value.isEmpty && (value as NSString).lastPathComponent == value
    }
}
