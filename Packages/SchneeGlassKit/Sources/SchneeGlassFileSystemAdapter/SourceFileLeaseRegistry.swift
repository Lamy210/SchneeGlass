import Darwin
import FileDomain
import Foundation
import SchneeGlassApplication

enum SourceFileLeaseError: Error, Hashable, Sendable {
    case sourceUnavailable
    case unsupportedItem
    case sourceChanged
    case permissionDenied
    case insufficientSpace
    case collision
    case stagingIdentityPreparationFailed
    case copyFailed(Int32)
}

struct PreparedSourceLease: Hashable, Sendable {
    let token: UUID
    let standardizedURL: URL
    let size: Int64
}

/// Keeps the exact source file opened at Drop planning time and binds that open descriptor to the
/// operation ID produced by DropPlanner. No descriptor crosses the actor boundary.
///
/// The pinned descriptor prevents same-path replacement, rename, or delete/recreate races from
/// changing which physical file is copied. Size and nanosecond mtime/ctime are checked immediately
/// before and after copying so in-place edits fail closed instead of committing a mixed snapshot.
public actor SourceFileLeaseRegistry {
    private struct Fingerprint: Hashable, Sendable {
        let size: Int64
        let device: UInt64
        let inode: UInt64
        let modificationSeconds: Int64
        let modificationNanoseconds: Int64
        let changeSeconds: Int64
        let changeNanoseconds: Int64

        init(metadata: stat) {
            self.size = metadata.st_size
            self.device = UInt64(metadata.st_dev)
            self.inode = UInt64(metadata.st_ino)
            self.modificationSeconds = Int64(metadata.st_mtimespec.tv_sec)
            self.modificationNanoseconds = Int64(metadata.st_mtimespec.tv_nsec)
            self.changeSeconds = Int64(metadata.st_ctimespec.tv_sec)
            self.changeNanoseconds = Int64(metadata.st_ctimespec.tv_nsec)
        }
    }

    private struct Lease {
        let descriptor: Int32
        let sourceURL: URL
        let fingerprint: Fingerprint
        var operationID: UUID?
        var executionActive: Bool
    }

    private static let defaultExpirationNanoseconds: UInt64 = 120_000_000_000

    private let expirationNanoseconds: UInt64
    private var leases: [UUID: Lease] = [:]
    private var tokenByOperationID: [UUID: UUID] = [:]
    private var operationIDBySourceURL: [URL: UUID] = [:]
    private var expirationTasks: [UUID: Task<Void, Never>] = [:]

    public init() {
        self.expirationNanoseconds = Self.defaultExpirationNanoseconds
    }

    init(expirationNanoseconds: UInt64) {
        self.expirationNanoseconds = expirationNanoseconds
    }

    func prepareSource(at url: URL) throws -> PreparedSourceLease {
        let source = url.standardizedFileURL
        let didStart = source.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let openResult = source.withUnsafeFileSystemRepresentation { path -> (descriptor: Int32, error: Int32)? in
            guard let path else {
                return nil
            }
            let descriptor = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
            return (descriptor, descriptor >= 0 ? 0 : errno)
        }

        guard let openResult else {
            throw SourceFileLeaseError.sourceUnavailable
        }
        guard openResult.descriptor >= 0 else {
            throw Self.mapOpenError(openResult.error)
        }

        let descriptor = openResult.descriptor
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            let observedErrno = errno
            close(descriptor)
            throw Self.mapOpenError(observedErrno)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            close(descriptor)
            throw SourceFileLeaseError.unsupportedItem
        }

        let token = UUID()
        let fingerprint = Fingerprint(metadata: metadata)
        leases[token] = Lease(
            descriptor: descriptor,
            sourceURL: source,
            fingerprint: fingerprint,
            operationID: nil,
            executionActive: false
        )
        scheduleExpiration(for: token)

        return PreparedSourceLease(
            token: token,
            standardizedURL: source,
            size: fingerprint.size
        )
    }

    func preparedSourceStillMatchesPath(token: UUID) -> Bool {
        guard let lease = leases[token], lease.operationID == nil else {
            return false
        }

        var metadata = stat()
        let result = lease.sourceURL.withUnsafeFileSystemRepresentation { path in
            guard let path else {
                return Int32(-1)
            }
            return lstat(path, &metadata)
        }
        guard result == 0,
              (metadata.st_mode & S_IFMT) == S_IFREG
        else {
            return false
        }

        let current = Fingerprint(metadata: metadata)
        return current.device == lease.fingerprint.device
            && current.inode == lease.fingerprint.inode
    }

    func bind(token: UUID, operationID: UUID) throws {
        guard var lease = leases[token], lease.operationID == nil else {
            throw SourceFileLeaseError.sourceUnavailable
        }

        // A newer plan may invalidate an older unconsumed plan, but it must never revoke source
        // authority that belongs to a batch whose copy execution has already begun.
        if let previousOperationID = operationIDBySourceURL[lease.sourceURL],
           previousOperationID != operationID
        {
            if let previousToken = tokenByOperationID[previousOperationID],
               leases[previousToken]?.executionActive == true
            {
                throw SourceFileLeaseError.sourceUnavailable
            }
            releaseBound(operationID: previousOperationID)
        }

        lease.operationID = operationID
        leases[token] = lease
        tokenByOperationID[operationID] = token
        operationIDBySourceURL[lease.sourceURL] = operationID
    }

    /// Marks every still-bound lease in a submitted batch as execution-active. Active leases are no
    /// longer stale-plan candidates: their TTL is cancelled and a newer plan for the same source
    /// cannot supersede them while earlier items in the batch are copying.
    func beginExecution(operationIDs: [UUID]) {
        for operationID in operationIDs {
            guard let token = tokenByOperationID[operationID],
                  var lease = leases[token],
                  lease.operationID == operationID
            else {
                continue
            }

            lease.executionActive = true
            leases[token] = lease
            expirationTasks.removeValue(forKey: token)?.cancel()
        }
    }

    func boundSourceSize(at sourceURL: URL) -> Int64? {
        let source = sourceURL.standardizedFileURL
        guard let operationID = operationIDBySourceURL[source],
              let token = tokenByOperationID[operationID],
              let lease = leases[token],
              lease.operationID == operationID
        else {
            return nil
        }
        return lease.fingerprint.size
    }

    func copyBoundSource(
        operationID: UUID,
        expectedSourceURL: URL,
        destinationDirectoryDescriptor: Int32,
        stagingFilename: String
    ) throws -> PreparedPendingCopyStaging {
        guard let token = tokenByOperationID[operationID],
              let lease = leases[token],
              lease.operationID == operationID,
              lease.sourceURL == expectedSourceURL.standardizedFileURL,
              DestinationDirectoryLeaseRegistry.stagingFilename(operationID: operationID) == stagingFilename
        else {
            throw SourceFileLeaseError.sourceUnavailable
        }

        // A bound lease is one-shot. Even a destination collision or copy error requires a new
        // Drop plan, which avoids accidentally reusing stale source authority.
        defer { releaseToken(token) }

        try Self.verifyUnchanged(lease)

        guard lseek(lease.descriptor, 0, SEEK_SET) >= 0 else {
            throw SourceFileLeaseError.sourceUnavailable
        }

        let destinationOpen = stagingFilename.withCString { name -> (descriptor: Int32, error: Int32) in
            let descriptor = openat(
                destinationDirectoryDescriptor,
                name,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o600)
            )
            return (descriptor, descriptor >= 0 ? 0 : errno)
        }
        guard destinationOpen.descriptor >= 0 else {
            throw Self.mapDestinationOpenError(destinationOpen.error)
        }

        let destinationDescriptor = destinationOpen.descriptor
        defer { close(destinationDescriptor) }

        guard fcopyfile(
            lease.descriptor,
            destinationDescriptor,
            nil,
            copyfile_flags_t(COPYFILE_ALL)
        ) == 0 else {
            throw Self.mapCopyError(errno)
        }

        // A writer can modify an already-open inode while fcopyfile is reading it. Verify the same
        // pinned descriptor again before this exact destination inode receives ownership proof.
        try Self.verifyUnchanged(lease)

        // Keep the destination descriptor open while inherited proof is removed and the fresh proof
        // is minted. The directory entry is revalidated through the already-pinned parent descriptor
        // before and after proof creation, so pathname replacement cannot receive recovery authority.
        guard let prepared = PendingCopyFileIdentity.prepareAppOwnedStaging(
            onFileDescriptor: destinationDescriptor,
            directoryDescriptor: destinationDirectoryDescriptor,
            filename: stagingFilename
        ) else {
            throw SourceFileLeaseError.stagingIdentityPreparationFailed
        }

        return prepared
    }

    func releasePrepared(tokens: [UUID]) {
        for token in tokens {
            guard leases[token]?.operationID == nil else {
                continue
            }
            releaseToken(token)
        }
    }

    func releaseBound(operationIDs: [UUID]) {
        for operationID in operationIDs {
            releaseBound(operationID: operationID)
        }
    }

    func activeLeaseCount() -> Int {
        leases.count
    }

    private func releaseBound(operationID: UUID) {
        guard let token = tokenByOperationID[operationID] else {
            return
        }
        releaseToken(token)
    }

    private func releaseToken(_ token: UUID) {
        expirationTasks.removeValue(forKey: token)?.cancel()
        guard let lease = leases.removeValue(forKey: token) else {
            return
        }

        if let operationID = lease.operationID {
            tokenByOperationID.removeValue(forKey: operationID)
            if operationIDBySourceURL[lease.sourceURL] == operationID {
                operationIDBySourceURL.removeValue(forKey: lease.sourceURL)
            }
        }
        close(lease.descriptor)
    }

    private func scheduleExpiration(for token: UUID) {
        // The task intentionally retains this registry until an unconsumed lease expires. Raw file
        // descriptors have no automatic Swift lifetime management; allowing the registry to
        // deinitialize first would orphan an open descriptor. Normal release or execution start
        // removes/cancels this task, breaking the temporary retention cycle immediately.
        let expirationNanoseconds = self.expirationNanoseconds
        expirationTasks[token] = Task { [self] in
            do {
                try await Task.sleep(nanoseconds: expirationNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            expire(token: token)
        }
    }

    private func expire(token: UUID) {
        releaseToken(token)
    }

    private static func verifyUnchanged(_ lease: Lease) throws {
        var currentMetadata = stat()
        guard fstat(lease.descriptor, &currentMetadata) == 0 else {
            throw SourceFileLeaseError.sourceUnavailable
        }
        guard Fingerprint(metadata: currentMetadata) == lease.fingerprint else {
            throw SourceFileLeaseError.sourceChanged
        }
    }

    private static func mapOpenError(_ error: Int32) -> SourceFileLeaseError {
        switch error {
        case EACCES, EPERM:
            return .permissionDenied
        case ELOOP:
            return .unsupportedItem
        default:
            return .sourceUnavailable
        }
    }

    private static func mapDestinationOpenError(_ error: Int32) -> SourceFileLeaseError {
        switch error {
        case EEXIST:
            return .collision
        case EACCES, EPERM:
            return .permissionDenied
        case ENOSPC, EDQUOT:
            return .insufficientSpace
        default:
            return .copyFailed(error)
        }
    }

    private static func mapCopyError(_ error: Int32) -> SourceFileLeaseError {
        switch error {
        case EACCES, EPERM:
            return .permissionDenied
        case ENOSPC, EDQUOT:
            return .insufficientSpace
        default:
            return .copyFailed(error)
        }
    }
}

/// File-system accessor used only by the production pinned-source copy path. Source data and the
/// destination directory are both descriptor-bound; staged size/ownership proof are served from
/// actor state without reopening the staging pathname.
private actor PinnedSourceCopyFileSystemAccessor: CopyFileSystemAccessing {
    private let sourceLeases: SourceFileLeaseRegistry
    private let destinationLeases: DestinationDirectoryLeaseRegistry
    private var preparedStagingByURL: [URL: PreparedPendingCopyStaging] = [:]

    init(
        sourceLeases: SourceFileLeaseRegistry,
        destinationLeases: DestinationDirectoryLeaseRegistry
    ) {
        self.sourceLeases = sourceLeases
        self.destinationLeases = destinationLeases
    }

    func sourceMetadata(at url: URL) async throws -> CopySourceMetadata {
        guard let size = await sourceLeases.boundSourceSize(at: url) else {
            throw CopyFileSystemError.sourceUnavailable
        }
        return CopySourceMetadata(size: size)
    }

    func isWritableDirectory(at url: URL) async -> Bool {
        await destinationLeases.isBoundDirectory(url)
    }

    func supportsCaseSensitiveNames(at url: URL) async -> Bool? {
        _ = url
        // The authoritative plan already captured this capability from the same directory identity
        // that DestinationDirectoryLeaseRegistry validates before mutation.
        return nil
    }

    func itemExists(at url: URL) async -> Bool {
        guard let exists = await destinationLeases.itemExists(at: url) else {
            // Unknown destination paths are never treated as absent in the production mutation path.
            return true
        }
        return exists
    }

    func copyItem(at sourceURL: URL, to stagingURL: URL) async throws {
        let staging = stagingURL.standardizedFileURL
        guard let operationID = await destinationLeases.operationID(forStagingURL: staging) else {
            throw CopyFileSystemError.destinationUnavailable
        }

        let directoryDescriptor: Int32
        do {
            directoryDescriptor = try await destinationLeases.duplicateDescriptor(
                operationID: operationID
            )
        } catch let error as DestinationDirectoryLeaseError {
            throw Self.map(error)
        }
        defer { close(directoryDescriptor) }

        do {
            let prepared = try await sourceLeases.copyBoundSource(
                operationID: operationID,
                expectedSourceURL: sourceURL,
                destinationDirectoryDescriptor: directoryDescriptor,
                stagingFilename: staging.lastPathComponent
            )
            preparedStagingByURL[staging] = prepared
        } catch let error as SourceFileLeaseError {
            throw Self.map(error)
        }
    }

    func regularFileSize(at url: URL) async throws -> Int64 {
        let staging = url.standardizedFileURL
        guard let prepared = preparedStagingByURL[staging] else {
            throw CopyFileSystemError.verificationFailed
        }
        return prepared.size
    }

    func resourceIdentifier(at url: URL) async -> String? {
        let staging = url.standardizedFileURL
        return preparedStagingByURL.removeValue(forKey: staging)?.resourceIdentifier
    }

    private static func map(_ error: SourceFileLeaseError) -> CopyFileSystemError {
        switch error {
        case .sourceUnavailable:
            return .sourceUnavailable
        case .unsupportedItem:
            return .unsupportedItem
        case .sourceChanged:
            return .verificationFailed
        case .permissionDenied:
            return .permissionDenied
        case .insufficientSpace:
            return .insufficientSpace
        case .collision:
            return .collision
        case .stagingIdentityPreparationFailed:
            return .verificationFailed
        case .copyFailed:
            return .unexpected
        }
    }

    private static func map(_ error: DestinationDirectoryLeaseError) -> CopyFileSystemError {
        switch error {
        case .permissionDenied:
            return .permissionDenied
        case .destinationUnavailable,
             .identityMismatch,
             .exclusiveRenameUnsupported,
             .operationNotBound:
            return .destinationUnavailable
        case .descriptorDuplicationFailed:
            return .unexpected
        }
    }
}

/// Production FileCopying facade that guarantees source and destination descriptor authority is
/// released after the batch result is produced, including preflight failures and tail items.
public actor PinnedSourceFileCopying: FileCopying {
    private let sourceLeases: SourceFileLeaseRegistry
    private let destinationLeases: DestinationDirectoryLeaseRegistry
    private let delegate: SafeFileCopyEngine

    public init(
        recoveryStore: any PendingCopyRecording,
        sourceLeases: SourceFileLeaseRegistry
    ) {
        let destinationLeases = DestinationDirectoryLeaseRegistry()
        self.sourceLeases = sourceLeases
        self.destinationLeases = destinationLeases
        self.delegate = SafeFileCopyEngine(
            fileSystem: PinnedSourceCopyFileSystemAccessor(
                sourceLeases: sourceLeases,
                destinationLeases: destinationLeases
            ),
            committer: PinnedDestinationStagingCommitter(
                destinationLeases: destinationLeases
            ),
            recoveryStore: recoveryStore
        )
    }

    public func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult {
        let operationIDs = request.plan.items.map(\.operationID)

        do {
            try await destinationLeases.bind(request)
        } catch let error as DestinationDirectoryLeaseError {
            await sourceLeases.releaseBound(operationIDs: operationIDs)
            return Self.destinationBindingFailure(request: request, error: error)
        } catch {
            await sourceLeases.releaseBound(operationIDs: operationIDs)
            return Self.destinationBindingFailure(
                request: request,
                error: .destinationUnavailable
            )
        }

        await sourceLeases.beginExecution(operationIDs: operationIDs)

        let result = await delegate.copy(request)
        await destinationLeases.release(batchID: request.plan.batchID)
        await sourceLeases.releaseBound(operationIDs: operationIDs)
        return result
    }

    private static func destinationBindingFailure(
        request: AuthorizedCopyBatchRequest,
        error: DestinationDirectoryLeaseError
    ) -> CopyBatchResult {
        guard let first = request.plan.items.first else {
            return CopyBatchResult(
                batchID: request.plan.batchID,
                succeeded: [],
                failed: nil,
                notAttempted: []
            )
        }

        let reason: CopyItemFailure.Reason
        switch error {
        case .permissionDenied:
            reason = .permissionDenied
        case .destinationUnavailable,
             .identityMismatch,
             .exclusiveRenameUnsupported,
             .operationNotBound,
             .descriptorDuplicationFailed:
            reason = .destinationUnavailable
        }

        return CopyBatchResult(
            batchID: request.plan.batchID,
            succeeded: [],
            failed: CopyItemFailure(
                operationID: first.operationID,
                reason: reason
            ),
            notAttempted: Array(request.plan.items.dropFirst())
        )
    }
}
