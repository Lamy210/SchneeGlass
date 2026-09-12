import Foundation
import FileDomain
import SchneeGlassDomain

public struct FolderAccessHandle: Hashable, Sendable {
    public let id: UUID
    public let glassID: GlassID
    public let url: URL
    public let fingerprint: ResourceFingerprint?
    public let runtimeDirectoryIdentity: RuntimeDirectoryIdentity?

    public init(
        id: UUID = UUID(),
        glassID: GlassID,
        url: URL,
        fingerprint: ResourceFingerprint? = nil,
        runtimeDirectoryIdentity: RuntimeDirectoryIdentity? = nil
    ) {
        self.id = id
        self.glassID = glassID
        self.url = url
        self.fingerprint = fingerprint
        self.runtimeDirectoryIdentity = runtimeDirectoryIdentity
    }
}

public struct FolderAccessAcquisition: Hashable, Sendable {
    public let handle: FolderAccessHandle
    public let refreshedSource: FolderSource?

    public init(handle: FolderAccessHandle, refreshedSource: FolderSource? = nil) {
        self.handle = handle
        self.refreshedSource = refreshedSource
    }
}

public enum FolderAccessError: Error, Hashable, Sendable {
    case bookmarkResolutionFailed
    case accessDenied
    case resourceReplacementDetected
}

public struct AuthorizedCopyBatchRequest: Hashable, Sendable {
    public let plan: CopyBatchPlan
    public let destinationAccess: FolderAccessHandle

    public init(plan: CopyBatchPlan, destinationAccess: FolderAccessHandle) {
        self.plan = plan
        self.destinationAccess = destinationAccess
    }
}

public struct CopyItemSuccess: Hashable, Sendable {
    public let operationID: UUID
    public let destinationURL: URL
    public let recoveryMetadataCleanupPending: Bool

    public init(
        operationID: UUID,
        destinationURL: URL,
        recoveryMetadataCleanupPending: Bool = false
    ) {
        self.operationID = operationID
        self.destinationURL = destinationURL
        self.recoveryMetadataCleanupPending = recoveryMetadataCleanupPending
    }
}

public struct CopyItemFailure: Error, Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        case sourceUnavailable
        case unsupportedItem
        case destinationUnavailable
        case permissionDenied
        case insufficientSpace
        case collision
        case verificationFailed
        case cancelled
        case unexpected
    }

    public let operationID: UUID
    public let reason: Reason

    public init(operationID: UUID, reason: Reason) {
        self.operationID = operationID
        self.reason = reason
    }
}

public struct CopyBatchResult: Hashable, Sendable {
    public let batchID: UUID
    public let succeeded: [CopyItemSuccess]
    public let failed: CopyItemFailure?
    public let notAttempted: [CopyItemPlan]

    public init(
        batchID: UUID,
        succeeded: [CopyItemSuccess],
        failed: CopyItemFailure?,
        notAttempted: [CopyItemPlan]
    ) {
        self.batchID = batchID
        self.succeeded = succeeded
        self.failed = failed
        self.notAttempted = notAttempted
    }
}

public struct CopyProgress: Hashable, Sendable {
    public let currentIndex: Int
    public let totalCount: Int
    public let currentFilename: String
    public let bytesCompleted: Int64?
    public let bytesTotal: Int64?

    public init(
        currentIndex: Int,
        totalCount: Int,
        currentFilename: String,
        bytesCompleted: Int64? = nil,
        bytesTotal: Int64? = nil
    ) {
        self.currentIndex = currentIndex
        self.totalCount = totalCount
        self.currentFilename = currentFilename
        self.bytesCompleted = bytesCompleted
        self.bytesTotal = bytesTotal
    }
}

public enum UnavailableReason: Hashable, Sendable {
    case permissionLost
    case sourceMissing
    case volumeUnavailable
    case bookmarkResolutionFailed
    case replacementDetected
    case unsupportedLocation
}

public enum GlassContentError: Error, Hashable, Sendable {
    case enumerationFailed
    case metadataFailed
    case unexpected
}

public enum GlassContentState: Hashable, Sendable {
    case loading
    case ready(FolderSnapshot)
    case empty(FolderSnapshot)
    case unavailable(UnavailableReason)
    case failed(GlassContentError)
}

public enum InteractionState: Hashable, Sendable {
    case idle
    case hovered
    case dropValid(DropPlan)
    case dropInvalid(DropRejection)
    case copying(CopyProgress)
}

public enum FileEvent: Hashable, Sendable {
    case changed
    case requiresFullRescan
    case rootChanged
}

public struct FileEventSubscription: Sendable {
    public let id: UUID
    public let events: AsyncStream<FileEvent>

    public init(id: UUID = UUID(), events: AsyncStream<FileEvent>) {
        self.id = id
        self.events = events
    }
}

public protocol FolderSnapshotReading: Sendable {
    func snapshot(for access: FolderAccessHandle, generation: UInt64) async throws -> FolderSnapshot
}

public protocol FolderAccessControlling: Sendable {
    func acquire(source: FolderSource, glassID: GlassID) async throws -> FolderAccessAcquisition
    func release(handleID: UUID) async
}

public protocol FileCopying: Sendable {
    func copy(_ request: AuthorizedCopyBatchRequest) async -> CopyBatchResult
}

/// Releases any planning-time authority held for an authorized copy request that will not execute.
/// Implementations must be idempotent because the same operation may already have been superseded or
/// consumed by another safety path before abandonment is observed.
public protocol AuthorizedCopyBatchAbandoning: Sendable {
    func abandon(_ request: AuthorizedCopyBatchRequest) async
}

public protocol ConfigurationPersisting: Sendable {
    func load() async throws -> [GlassConfiguration]
    func save(_ configurations: [GlassConfiguration]) async throws
}

/// Persistence capability for read-modify-write configuration commands.
///
/// Implementations must compare `expectedCurrent` and commit `configurations` as one serialized
/// persistence operation. Returning `false` means another writer changed the current configuration;
/// callers must not retry with their stale derived value.
public protocol ConditionalConfigurationPersisting: ConfigurationPersisting {
    func save(
        _ configurations: [GlassConfiguration],
        ifCurrentMatches expectedCurrent: [GlassConfiguration]
    ) async throws -> Bool
}

public protocol FileEventStreaming: Sendable {
    func subscribe(for access: FolderAccessHandle) async throws -> FileEventSubscription
    func stop(subscriptionID: UUID) async
}

public protocol WindowControlling: Sendable {
    func show(glassID: GlassID) async
    func hide(glassID: GlassID) async
    func remove(glassID: GlassID) async
}
