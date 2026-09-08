import SchneeGlassDomain

public enum UpdateGlassPlacementError: Error, Hashable, Sendable {
    case configurationLoadFailed
    case invalidConfiguration
    case configurationSaveFailed
}

public actor UpdateGlassPlacementUseCase {
    private let configurationStore: any ConfigurationPersisting

    public init(configurationStore: any ConfigurationPersisting) {
        self.configurationStore = configurationStore
    }

    @discardableResult
    public func execute(
        glassID: GlassID,
        placement: GlassPlacement
    ) async throws -> Bool {
        var configurations: [GlassConfiguration]
        do {
            configurations = try await configurationStore.load()
        } catch {
            throw UpdateGlassPlacementError.configurationLoadFailed
        }

        guard let index = configurations.firstIndex(where: { $0.id == glassID }) else {
            return false
        }

        let current = configurations[index]
        let updated: GlassConfiguration
        do {
            updated = try GlassConfiguration(
                id: current.id,
                title: current.title,
                source: current.source,
                placement: placement,
                showOnAllSpaces: current.showOnAllSpaces,
                createdAt: current.createdAt
            )
        } catch {
            throw UpdateGlassPlacementError.invalidConfiguration
        }

        guard updated != current else {
            return true
        }

        configurations[index] = updated
        do {
            try await configurationStore.save(configurations)
        } catch {
            throw UpdateGlassPlacementError.configurationSaveFailed
        }

        return true
    }
}
