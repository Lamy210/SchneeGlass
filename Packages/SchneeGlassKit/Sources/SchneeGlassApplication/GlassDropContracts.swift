import FileDomain
import Foundation

public protocol DropPlanning: AuthorizedCopyBatchAbandoning {
    /// Advisory planning for hover/validation UI. Implementations may override this to avoid
    /// acquiring mutation authority or other resources that should exist only for execution.
    func preview(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan

    /// Authoritative planning immediately before copy execution.
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan
}

public extension DropPlanning {
    func preview(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan {
        await plan(
            sourceURLs: sourceURLs,
            destinationAccess: destinationAccess
        )
    }

    /// Lease-free planners have nothing to release. Any implementation that acquires planning-time
    /// authority must override this default so a superseded or stopped runtime can relinquish it.
    func abandon(_ request: AuthorizedCopyBatchRequest) async {
        _ = request
    }
}

public enum GlassCopyExecutionError: Error, Hashable, Sendable {
    case sessionNotRunning
    case copyInProgress
    case destinationMismatch
}
