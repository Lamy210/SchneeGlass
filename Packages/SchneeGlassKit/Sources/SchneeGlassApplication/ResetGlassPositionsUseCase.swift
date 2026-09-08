import SchneeGlassDomain

public enum ResetGlassPositionsError: Error, Hashable, Sendable {
    case configurationLoadFailed
    case configurationChanged
    case invalidConfiguration
    case configurationSaveFailed
}

/// Atomically applies a complete set of planned Glass placements.
///
/// The caller is responsible for calculating screen-safe placements before invoking this use case.
/// This type deliberately knows nothing about AppKit or displays; its only responsibility is to
/// replace the requested placement values in one configuration transaction.
public actor ResetGlassPositionsUseCase {
    private let configurationStore: any ConfigurationPersisting

    public init(configurationStore: any ConfigurationPersisting) {
        self.configurationStore = configurationStore
    }

    @discardableResult
    public func execute(
        placements: [GlassID: GlassPlacement]
    ) async throws -> [GlassConfiguration] {
        let configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw ResetGlassPositionsError.configurationLoadFailed
        }

        guard !placements.isEmpty else {
            return configurations
        }

        let persistedIDs = Set(configurations.map(\.id))
        guard Set(placements.keys).isSubset(of: persistedIDs) else {
            // The workspace snapshot and persisted configuration no longer agree. Refuse to
            // partially apply a recovery layout and let the caller retry from fresh state.
            throw ResetGlassPositionsError.configurationChanged
        }

        var updatedConfigurations = configurations
        var changed = false

        for index in updatedConfigurations.indices {
            let current = updatedConfigurations[index]
            guard let placement = placements[current.id],
                  placement != current.placement
            else {
                continue
            }

            do {
                updatedConfigurations[index] = try GlassConfiguration(
                    id: current.id,
                    title: current.title,
                    source: current.source,
                    placement: placement,
                    showOnAllSpaces: current.showOnAllSpaces,
                    createdAt: current.createdAt
                )
            } catch {
                throw ResetGlassPositionsError.invalidConfiguration
            }
            changed = true
        }

        guard changed else {
            return updatedConfigurations
        }

        do {
            // One save is the atomic boundary. Never persist Glass placements one-by-one here.
            try await configurationStore.save(updatedConfigurations)
        } catch {
            throw ResetGlassPositionsError.configurationSaveFailed
        }

        return updatedConfigurations
    }
}
