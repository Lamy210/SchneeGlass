import FileDomain
import Foundation
import SchneeGlassDomain

public enum RemoveGlassError: Error, Hashable, Sendable {
    case configurationLoadFailed
    case pendingCopyLoadFailed
    case pendingCopyRecoveryRequired
    case configurationSaveFailed
}

public actor RemoveGlassUseCase {
    private let configurationStore: any ConfigurationPersisting
    private let pendingCopyStore: any PendingCopyRecording

    public init(
        configurationStore: any ConfigurationPersisting,
        pendingCopyStore: any PendingCopyRecording
    ) {
        self.configurationStore = configurationStore
        self.pendingCopyStore = pendingCopyStore
    }

    public func execute(glassID: GlassID) async throws -> Bool {
        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw RemoveGlassError.configurationLoadFailed
        }

        guard configurations.contains(where: { $0.id == glassID }) else {
            return false
        }

        let pendingCopies: [PendingCopyRecord]
        do {
            pendingCopies = try await pendingCopyStore.records()
        } catch {
            throw RemoveGlassError.pendingCopyLoadFailed
        }

        guard !pendingCopies.contains(where: { $0.destinationGlassID == glassID }) else {
            throw RemoveGlassError.pendingCopyRecoveryRequired
        }

        let remaining = configurations.filter { $0.id != glassID }
        do {
            try await configurationStore.save(remaining)
        } catch {
            throw RemoveGlassError.configurationSaveFailed
        }

        return true
    }
}

@MainActor
public protocol WorkspaceFileActing: Sendable {
    func open(url: URL) -> Bool
    func reveal(url: URL)
}

public enum WorkspaceFileActionError: Error, Hashable, Sendable {
    case openFailed
}

@MainActor
public final class WorkspaceFileActionUseCase {
    private let actor: any WorkspaceFileActing

    public init(actor: any WorkspaceFileActing) {
        self.actor = actor
    }

    public func open(_ item: GlassItem) throws {
        guard actor.open(url: item.url) else {
            throw WorkspaceFileActionError.openFailed
        }
    }

    public func reveal(_ item: GlassItem) {
        actor.reveal(url: item.url)
    }
}
