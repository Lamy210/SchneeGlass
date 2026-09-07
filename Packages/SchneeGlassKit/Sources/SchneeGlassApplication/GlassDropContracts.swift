import FileDomain
import Foundation

public protocol DropPlanning: Sendable {
    func plan(
        sourceURLs: [URL],
        destinationAccess: FolderAccessHandle
    ) async -> DropPlan
}

public enum GlassCopyExecutionError: Error, Hashable, Sendable {
    case sessionNotRunning
    case copyInProgress
    case destinationMismatch
}
