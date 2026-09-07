import FileDomain
import Foundation
import SchneeGlassDomain

public enum RemoveGlassError: Error, Hashable, Sendable {
    case configurationLoadFailed
    case configurationSaveFailed
}

public actor RemoveGlassUseCase {
    private let configurationStore: any ConfigurationPersisting

    public init(configurationStore: any ConfigurationPersisting) {
        self.configurationStore = configurationStore
    }

    public func execute(glassID: GlassID) async throws -> Bool {
        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw RemoveGlassError.configurationLoadFailed
        }

        let remaining = configurations.filter { $0.id != glassID }
        guard remaining.count != configurations.count else {
            return false
        }

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
