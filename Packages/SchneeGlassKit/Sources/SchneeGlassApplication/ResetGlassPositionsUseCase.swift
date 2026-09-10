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
    private let configurationStore: any ConditionalConfigurationPersisting

    public init(configurationStore: any ConditionalConfigurationPersisting) {
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
        guard Set(placements.keys) == persistedIDs else {
            // Reset is an all-Glass recovery operation. If either the workspace snapshot or the
            // persisted configuration contains a Glass the other side does not know about, the
            // snapshot is stale. Refuse to save a partial recovery layout and let the caller retry
            // from freshly restored state.
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
            // The store compares and commits as one serialized persistence operation. Never let a
            // layout calculated from an older snapshot overwrite a newer configuration generation.
            guard try await configurationStore.save(
                updatedConfigurations,
                ifCurrentMatches: configurations
            ) else {
                throw ResetGlassPositionsError.configurationChanged
            }
        } catch let error as ResetGlassPositionsError {
            throw error
        } catch {
            throw ResetGlassPositionsError.configurationSaveFailed
        }

        return updatedConfigurations
    }
}
