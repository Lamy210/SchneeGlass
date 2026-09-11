import Foundation
import FileDomain
import SchneeGlassDomain

@MainActor
public protocol FolderSelecting: Sendable {
    func selectFolder() async -> URL?
}

public enum FolderSourceCreationError: Error, Hashable, Sendable {
    case bookmarkCreationFailed
    case resourceIdentityUnavailable
}

public protocol FolderSourceCreating: Sendable {
    func createSource(for selectedURL: URL) async throws -> FolderSource
}

@MainActor
public protocol InitialGlassPlacementProviding: Sendable {
    func initialPlacement() throws -> GlassPlacement
}

public struct CreatedGlassRuntimeSeed: Sendable {
    public let configuration: GlassConfiguration
    public let access: FolderAccessHandle
    public let snapshot: FolderSnapshot
    public let eventSubscription: FileEventSubscription

    public init(
        configuration: GlassConfiguration,
        access: FolderAccessHandle,
        snapshot: FolderSnapshot,
        eventSubscription: FileEventSubscription
    ) {
        self.configuration = configuration
        self.access = access
        self.snapshot = snapshot
        self.eventSubscription = eventSubscription
    }
}

public enum CreateGlassError: Error, Hashable, Sendable {
    case sourceCreationFailed
    case placementUnavailable
    case invalidConfiguration
    case configurationLoadFailed
    case folderAccess(FolderAccessError)
    case eventStreamFailed
    case snapshotFailed
    case configurationSaveFailed
}
