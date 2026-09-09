import FileDomain
import Foundation

public protocol DropPlanning: Sendable {
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
}

public enum GlassCopyExecutionError: Error, Hashable, Sendable {
    case sessionNotRunning
    case copyInProgress
    case destinationMismatch
}
